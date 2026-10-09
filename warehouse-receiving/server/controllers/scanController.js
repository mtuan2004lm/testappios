const db = require('../config/db');
const { HttpError, asyncHandler, parseId } = require('../utils/http');
const { matchRule } = require('../utils/ruleMatcher');
const { matchProduct } = require('../utils/trackingFormats');

// Ma QR "END CODE" (1 ma co dinh dung chung, in san): ket thuc mot tem khi ca 3 tracking deu khong co thong tin
const isEndCode = (code) => /^END[\s_-]?CODE$/i.test(String(code || '').trim());
// CHE DO THU: false = cho phep quet lai cung mot ma nhieu lan (de test voi vai ma mau). Chi chan trung khi dat BLOCK_DUPLICATES=true.
// (Giua cac phien khac nhau thi luon quet lai duoc: chi chan trung trong CUNG MOT phien.)
const BLOCK_DUPLICATES = process.env.BLOCK_DUPLICATES === 'true';
const MAX_TRACKS = 3;   // toi da 3 ma tracking tren mot tem

// POST /api/v1/receiving/sessions/:id/scan   body: { barcode, detected_text, scanned_by? }
// Quy trinh quet tuan tu tren mot tem (moi lan goi = 1 ma):
//  - ma co trong Danh sach mat hang  -> YES: ghi 1 kien (cac ma truoc do tren tem duoc gan vao kien)
//  - ma khong co thong tin           -> TING: ghi lai ma (tracking 1/2/3), cho ma tiep theo
//  - da co 3 ma khong thong tin      -> chan: bat buoc quet QR END CODE (409 END_CODE_REQUIRED)
//  - quet QR END CODE                -> ghi 1 kien NO NAME, lay tracking dau lam tracking goc
exports.scan = asyncHandler(async (req, res) => {
  const sessionId = parseId(req.params.id);
  // Bo ky tu dieu khien an trong ma vach (vd GS \x1D cua GS1-128: "42097220<GS>9334...") roi moi so khop / luu
  const barcode = String((req.body && req.body.barcode) || '').replace(/[\x00-\x1F\x7F]/g, '').trim();
  // detected_text la chuoi ma kho doc tu nhan; neu app khong gui thi dung chinh barcode de khop
  const detectedText = String((req.body && req.body.detected_text) || '').trim() || barcode;
  const scannedBy = (req.body && req.body.scanned_by) || null;

  if (!barcode) throw new HttpError(400, 'barcode là bắt buộc', 'BARCODE_REQUIRED');
  if (barcode.length > 100) throw new HttpError(400, 'barcode tối đa 100 ký tự', 'BARCODE_TOO_LONG');

  const client = await db.getClient();
  try {
    await client.query('BEGIN');

    // Khoa dong phien de cac luot quet dong thoi khong lam sai scanned_count
    const s = await client.query('SELECT * FROM receiving_sessions WHERE id = $1 FOR UPDATE', [sessionId]);
    if (!s.rows.length) throw new HttpError(404, 'Không tìm thấy phiên', 'SESSION_NOT_FOUND');
    if (s.rows[0].status !== 'OPEN') throw new HttpError(409, 'Phiên đã đóng, không thể quét thêm', 'SESSION_CLOSED');

    // Cac tracking chua co thong tin cua tem dang quet do
    const pending = (await client.query(
      'SELECT * FROM label_scans WHERE session_id = $1 AND item_id IS NULL ORDER BY seq, id', [sessionId])).rows;

    // Ma kho: uu tien chu doc tu nhan (app) -> khop regex quy tac
    const hasExplicitText = detectedText !== barcode;
    const reg = (await client.query('SELECT warehouse_code FROM tracking_codes WHERE barcode = $1', [barcode])).rows[0];
    const rules = (await client.query('SELECT * FROM warehouse_rules WHERE is_active = TRUE ORDER BY id')).rows;
    const textForRule = (txt) => matchRule(txt, rules);

    // Tao kien tu mot tem: tracking goc + cac tracking truoc do ttren tem
    const makeItem = async ({ rootCode, product, carrier, matched, text, noName }) => {
      const explicit = !!text && text !== rootCode;
      const mt = explicit ? text : ((reg && reg.warehouse_code) || text || rootCode);
      const rule = textForRule(mt);
      const ins = await client.query(
        `INSERT INTO scanned_items
           (session_id, barcode, detected_warehouse_code, matched_rule_id, customer_group, business_type, exception_status, scanned_by,
            detected_carrier, matched_tracking, product_id, is_no_name)
         VALUES ($1, $2, $3, $4, $5, $6, 'NORMAL', COALESCE($7, 'Nhan vien 01'), $8, $9, $10, $11)
         RETURNING *`,
        [sessionId, rootCode, (rule || explicit) ? mt : null, rule ? rule.id : null, rule ? rule.customer_group : null,
         rule ? rule.business_type : null, scannedBy, carrier, matched, product ? product.id : null, !!noName]);
      return { item: ins.rows[0], rule, mt };
    };
    const dupResponse = async (code) => {
      const up = await client.query(
        `UPDATE receiving_sessions
            SET duplicate_count = duplicate_count + 1, last_scan_status = 'DUPLICATE', last_scan_at = CURRENT_TIMESTAMP,
                last_scan_barcode = $2, last_scan_text = NULL, last_scan_group = NULL, last_scan_exception = NULL
          WHERE id = $1 RETURNING duplicate_count`, [sessionId, code]);
      await client.query('COMMIT');
      return res.status(409).json({
        error: { code: 'DUPLICATE_BARCODE', message: `Mã ${code} đã được quét trong phiên này` },
        data: { barcode: code, exception_status: 'DUPLICATE', duplicate_count: up.rows[0].duplicate_count },
      });
    };
    const successResponse = async ({ item, rule, mt }, { carrier, method, tracks, status, noName }) => {
      const up = await client.query(
        `UPDATE receiving_sessions
            SET scanned_count = scanned_count + 1,
                last_scan_status = $6, last_scan_at = CURRENT_TIMESTAMP, last_scan_barcode = $2,
                last_scan_text = $3, last_scan_group = $4, last_scan_exception = $5
          WHERE id = $1 RETURNING scanned_count, total_expected_packages`,
        [sessionId, item.barcode, mt, rule ? rule.customer_group : null, 'NORMAL', status]);
      // Gan cac tracking cua tem nay vao kien
      await client.query('UPDATE label_scans SET item_id = $2 WHERE session_id = $1 AND item_id IS NULL', [sessionId, item.id]);
      await client.query('COMMIT');
      const isBusiness = item.business_type === 'KINH_DOANH';
      return res.status(201).json({
        data: {
          status, sound: noName ? 'TING' : 'YES',
          item, scanned_count: up.rows[0].scanned_count, total_expected_packages: up.rows[0].total_expected_packages,
          in_registry: !noName, no_name: !!noName, carrier, match_method: method || null, tracks,
          requires_import_check: !!(rule && rule.requires_import_check),
          warning: noName ? 'NO NAME - cả 3 tracking không có thông tin, đã lấy tracking đầu làm tracking gốc'
            : (isBusiness ? 'HÀNG KINH DOANH - cần kiểm tra điều kiện nhập khẩu trước khi nhập kho'
              : (rule ? null : 'Chưa xác định được nhóm khách hàng từ mã kho')),
        },
      });
    };

    // ---- 1) QR END CODE ----
    if (isEndCode(barcode)) {
      if (!pending.length) {
        await client.query('ROLLBACK');
        throw new HttpError(409, 'Chưa có tracking nào đang chờ — END CODE chỉ dùng sau khi quét tracking không có thông tin', 'NO_PENDING_TRACKS');
      }
      const root = pending[0];
      const text = pending.map((p) => p.detected_text).find((t, i) => t && t !== pending[i].barcode) || root.detected_text;
      // Tracking dau co the da duoc quet trung o kien khac -> bao trung
      if (BLOCK_DUPLICATES && (await client.query('SELECT 1 FROM scanned_items WHERE session_id = $1 AND matched_tracking = $2 LIMIT 1', [sessionId, root.barcode])).rows.length) return dupResponse(root.barcode);
      const made = await makeItem({ rootCode: root.barcode, product: null, carrier: root.carrier, matched: root.barcode, text, noName: true });
      if (!made.item) return dupResponse(root.barcode);   // (khong con xay ra: da bo rang buoc unique)
      return successResponse(made, { carrier: root.carrier, method: null, status: 'NO_NAME', noName: true,
        tracks: pending.map((p) => ({ seq: p.seq, barcode: p.barcode })) });
    }

    // ---- 2) Tracking binh thuong ----
    // Da du 3 tracking khong co thong tin ma chua quet END CODE -> chan
    if (pending.length >= MAX_TRACKS) {
      await client.query('ROLLBACK');
      throw new HttpError(409, 'Đã quét đủ 3 tracking không có thông tin — bắt buộc quét QR END CODE trước khi quét tiếp', 'END_CODE_REQUIRED',
        { pending: pending.map((p) => ({ seq: p.seq, barcode: p.barcode })) });
    }
    // Ma nay da quet (chua co thong tin) tren tem dang do -> khong ghi lai
    if (BLOCK_DUPLICATES && pending.some((p) => p.barcode.toUpperCase() === barcode.toUpperCase())) {
      await client.query('ROLLBACK');
      throw new HttpError(409, `Mã ${barcode} vừa quét ở tem này`, 'DUPLICATE_BARCODE');
    }

    const m = await matchProduct(client, barcode, s.rows[0].carrier_name);
    const candidates = m.candidates.map((c) => c.value);

    if (m.product) {
      // Cung mot kien co the co nhieu ma (toi da 3 ma tren tem) -> chan trung theo mat hang da khop
      const sameParcel = BLOCK_DUPLICATES && (await client.query(
        'SELECT 1 FROM scanned_items WHERE session_id = $1 AND (product_id = $3 OR matched_tracking = $2) LIMIT 1', [sessionId, m.matched || barcode, m.product.id])).rows.length > 0;
      if (sameParcel) return dupResponse(barcode);
      const made = await makeItem({ rootCode: barcode, product: m.product, carrier: m.carrier, matched: m.matched || barcode, text: detectedText });
      if (!made.item) return dupResponse(barcode);
      // Luu tracking co thong tin thanh ma thu (pending.length + 1) cua tem
      await client.query(
        'INSERT INTO label_scans (session_id, seq, barcode, product_id, carrier, detected_text) VALUES ($1,$2,$3,$4,$5,$6)',
        [sessionId, pending.length + 1, barcode, m.product.id, m.carrier, detectedText]);
      return successResponse(made, { carrier: m.carrier, method: m.method, status: 'SUCCESS',
        tracks: [...pending.map((p) => ({ seq: p.seq, barcode: p.barcode, matched: false })), { seq: pending.length + 1, barcode, matched: true }] });
    }

    // Khong co thong tin -> ghi lai tracking (TING), cho ma tiep theo
    const seq = pending.length + 1;
    await client.query(
      'INSERT INTO label_scans (session_id, seq, barcode, carrier, detected_text) VALUES ($1,$2,$3,$4,$5)',
      [sessionId, seq, barcode, m.carrier, detectedText]);
    await client.query(
      `UPDATE receiving_sessions
          SET last_scan_status = 'TRACK', last_scan_at = CURRENT_TIMESTAMP, last_scan_barcode = $2,
              last_scan_text = $3, last_scan_group = $4, last_scan_exception = $5
        WHERE id = $1`, [sessionId, barcode, hasExplicitText ? detectedText : null, null, String(seq)]);
    await client.query('COMMIT');
    console.log(`[scan] TRACK ${seq}/3 phien ${sessionId}: "${barcode}" chua co thong tin, da thu:`, candidates);
    return res.status(200).json({
      data: {
        status: 'TRACK', sound: 'TING', seq, max: MAX_TRACKS, need_end_code: seq >= MAX_TRACKS,
        barcode, carrier: m.carrier, tried: candidates,
        pending: [...pending.map((p) => ({ seq: p.seq, barcode: p.barcode })), { seq, barcode }],
      },
    });
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
});

// POST /api/v1/receiving/sessions/:id/scan-fail   body: { detected_text }
// App iOS: khong doc duoc barcode nhung doc duoc ma kho tren nhan -> ghi FAIL (khong tao kien) de web bao FAIL.
// Chi ghi khi ma kho khop mot quy tac; neu khong khop thi coi la nhieu, bo qua.
exports.scanFail = asyncHandler(async (req, res) => {
  const sessionId = parseId(req.params.id);
  const text = String((req.body && req.body.detected_text) || '').trim().slice(0, 100);
  if (!text) throw new HttpError(400, 'detected_text là bắt buộc', 'TEXT_REQUIRED');

  const s = await db.query('SELECT status FROM receiving_sessions WHERE id = $1', [sessionId]);
  if (!s.rows.length) throw new HttpError(404, 'Không tìm thấy phiên', 'SESSION_NOT_FOUND');
  if (s.rows[0].status !== 'OPEN') throw new HttpError(409, 'Phiên đã đóng', 'SESSION_CLOSED');

  const rules = (await db.query('SELECT * FROM warehouse_rules WHERE is_active = TRUE ORDER BY id')).rows;
  const rule = matchRule(text, rules);
  if (!rule) throw new HttpError(422, 'Mã kho không khớp quy tắc nào, bỏ qua', 'WAREHOUSE_CODE_NOT_MATCHED');

  const { rows } = await db.query(
    `UPDATE receiving_sessions
        SET fail_count = fail_count + 1, last_scan_status = 'FAIL', last_scan_at = CURRENT_TIMESTAMP,
            last_scan_barcode = NULL, last_scan_text = $2, last_scan_group = $3, last_scan_exception = NULL
      WHERE id = $1 RETURNING fail_count`, [sessionId, text, rule.customer_group]);
  res.status(201).json({ data: { status: 'FAIL', detected_text: text, customer_group: rule.customer_group, fail_count: rows[0].fail_count } });
});

// POST /api/v1/receiving/sessions/:id/classify   body: { barcode, detected_text }
// Module 2 cua app iOS: kien da quet nhap kho, nay doc ma kho tren nhan de gan nhom khach hang.
exports.classify = asyncHandler(async (req, res) => {
  const sessionId = parseId(req.params.id);
  const barcode = String((req.body && req.body.barcode) || '').trim();
  const text = String((req.body && req.body.detected_text) || '').trim();
  if (!barcode || !text) throw new HttpError(400, 'barcode và detected_text là bắt buộc', 'FIELDS_REQUIRED');

  const found = await db.query('SELECT * FROM scanned_items WHERE session_id = $1 AND barcode = $2', [sessionId, barcode]);
  if (!found.rows.length) throw new HttpError(404, 'Kiện này chưa được quét nhập kho trong phiên', 'ITEM_NOT_SCANNED');

  const rules = (await db.query('SELECT * FROM warehouse_rules WHERE is_active = TRUE ORDER BY id')).rows;
  const rule = matchRule(text, rules);
  if (!rule) return res.json({ data: { item: found.rows[0], matched: false, warning: 'Mã kho không khớp quy tắc nào' } });

  const upd = await db.query(
    `UPDATE scanned_items
        SET detected_warehouse_code = $2, matched_rule_id = $3, customer_group = $4, business_type = $5,
            exception_status = CASE WHEN exception_status = 'UNKNOWN' THEN 'NORMAL'::item_exception_enum ELSE exception_status END
      WHERE id = $1 RETURNING *`,
    [found.rows[0].id, text, rule.id, rule.customer_group, rule.business_type]);
  // Luu mã kho vao danh sach tracking de cac lan quet sau tu nhan nhom
  await db.query(
    `INSERT INTO tracking_codes (barcode, warehouse_code) VALUES ($1, $2)
     ON CONFLICT (barcode) DO UPDATE SET warehouse_code = EXCLUDED.warehouse_code`, [barcode, text]);

  res.json({ data: {
    item: upd.rows[0], matched: true, requires_import_check: !!rule.requires_import_check,
    warning: rule.business_type === 'KINH_DOANH' ? 'HÀNG KINH DOANH - cần kiểm tra điều kiện nhập khẩu trước khi nhập kho' : null,
  } });
});
