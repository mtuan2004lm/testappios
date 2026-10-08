const db = require('../config/db');
const { HttpError, asyncHandler, parseId } = require('../utils/http');
const { matchRule } = require('../utils/ruleMatcher');

// POST /api/v1/receiving/sessions/:id/scan   body: { barcode, detected_text, scanned_by? }
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

    // Tra cuu ma trong danh sach tracking du kien (neu co warehouse_code thi uu tien dung de khop rule)
    // Chi ma co trong "Danh sach mat hang" (cot Tracking hoac Ma khac) moi duoc coi la xac dinh; con lai la UNKNOWN
    const reg = (await client.query('SELECT warehouse_code FROM tracking_codes WHERE barcode = $1', [barcode])).rows[0];
    // Tem USPS: ma vach = "420" + ZIP (5 hoac 9 so) + tracking that (vd 420 97220 9334610990150197272857)
    // -> ngoai chinh ma quet, thu them phan tracking sau tien to 420+ZIP.
    const candidates = [barcode];
    if (/^420\d{13,}$/.test(barcode)) { candidates.push(barcode.slice(8)); if (barcode.length > 12) candidates.push(barcode.slice(12)); }
    const normBarcode = barcode.replace(/\s/g, '').toUpperCase();
    const inRegistry = (await client.query(
      // So sanh khong phan biet hoa/thuong va bo qua khoang trang thua trong danh sach.
      // Nhan FedEx / UPS...: ma vach dai (vd 34 so) co chua ma tracking in tren nhan (vd 12 so cuoi)
      // -> neu ma trong danh sach dai >= 10 ky tu va nam trong ma vach thi cung tinh la khop.
      `SELECT 1 FROM products p,
              LATERAL (SELECT UPPER(regexp_replace(p.tracking_code, '\\s', '', 'g')) AS t,
                              UPPER(regexp_replace(COALESCE(p.alt_code, ''), '\\s', '', 'g')) AS a) n
        WHERE n.t = ANY($1) OR n.a = ANY($1)
           OR (LENGTH(n.t) >= 10 AND strpos($2, n.t) > 0)
           OR (LENGTH(n.a) >= 10 AND strpos($2, n.a) > 0)
        LIMIT 1`,
      [candidates.map((c) => c.replace(/\s/g, '').toUpperCase()), normBarcode])).rows.length > 0;
    // App iOS gui ma kho doc duoc tu nhan (detected_text khac barcode) -> uu tien dung, vi la du lieu moi nhat
    const hasExplicitText = detectedText !== barcode;
    const matchText = hasExplicitText ? detectedText : ((reg && reg.warehouse_code) || detectedText);

    // Khop regex voi cac rule dang bat
    const rules = (await client.query('SELECT * FROM warehouse_rules WHERE is_active = TRUE ORDER BY id')).rows;
    const rule = matchRule(matchText, rules);

    // Ma KHONG co trong Danh sach mat hang -> tu choi (FAIL): khong tao kien, khong tinh vao so da quet
    if (!inRegistry) {
      console.log(`[scan] FAIL phien ${sessionId}: ma quet "${barcode}" (${barcode.length} ky tu), da thu so voi danh sach:`, candidates);
      await client.query(
        `UPDATE receiving_sessions
            SET fail_count = fail_count + 1, last_scan_status = 'FAIL', last_scan_at = CURRENT_TIMESTAMP,
                last_scan_barcode = $2, last_scan_text = $3, last_scan_group = $4, last_scan_exception = 'NOT_FOUND'
          WHERE id = $1`, [sessionId, barcode, matchText, rule ? rule.customer_group : null]);
      await client.query('COMMIT');
      return res.status(422).json({
        error: { code: 'TRACKING_NOT_FOUND', message: `FAIL: mã ${barcode} không có trong danh sách mặt hàng` },
        data: { barcode, status: 'FAIL', customer_group: rule ? rule.customer_group : null },
      });
    }

    // ON CONFLICT bat loi trung (session_id, barcode) ma khong lam hong transaction
    const ins = await client.query(
      `INSERT INTO scanned_items
         (session_id, barcode, detected_warehouse_code, matched_rule_id, customer_group, business_type, exception_status, scanned_by)
       VALUES ($1, $2, $3, $4, $5, $6, $7, COALESCE($8, 'Nhan vien 01'))
       ON CONFLICT ON CONSTRAINT unique_barcode_per_session DO NOTHING
       RETURNING *`,
      // Ma kho chi luu khi that su doc/khop duoc (go tay ma vach tren web thi de trong, khong lap lai chinh barcode)
      [sessionId, barcode, (rule || hasExplicitText) ? matchText : null, rule ? rule.id : null, rule ? rule.customer_group : null,
       rule ? rule.business_type : null,
       'NORMAL', scannedBy]   // toi day ma chac chan co trong Danh sach mat hang
    );

    if (!ins.rows.length) {
      // Ma da quet trong phien nay -> tang bo dem trung, tra 409
      const up = await client.query(
        `UPDATE receiving_sessions
            SET duplicate_count = duplicate_count + 1, last_scan_status = 'DUPLICATE', last_scan_at = CURRENT_TIMESTAMP,
                last_scan_barcode = $2, last_scan_text = NULL, last_scan_group = NULL, last_scan_exception = NULL
          WHERE id = $1 RETURNING duplicate_count`, [sessionId, barcode]);
      await client.query('COMMIT');
      return res.status(409).json({
        error: { code: 'DUPLICATE_BARCODE', message: `Mã ${barcode} đã được quét trong phiên này` },
        data: { barcode, exception_status: 'DUPLICATE', duplicate_count: up.rows[0].duplicate_count },
      });
    }

    const up = await client.query(
      `UPDATE receiving_sessions
          SET scanned_count = scanned_count + 1,
              last_scan_status = 'SUCCESS', last_scan_at = CURRENT_TIMESTAMP, last_scan_barcode = $2,
              last_scan_text = $3, last_scan_group = $4, last_scan_exception = $5
        WHERE id = $1 RETURNING scanned_count, total_expected_packages`,
      [sessionId, barcode, matchText, rule ? rule.customer_group : null, 'NORMAL']);
    await client.query('COMMIT');

    const item = ins.rows[0];
    const isBusiness = item.business_type === 'KINH_DOANH';
    res.status(201).json({
      data: {
        item,
        scanned_count: up.rows[0].scanned_count,
        total_expected_packages: up.rows[0].total_expected_packages,
        in_registry: inRegistry,
        requires_import_check: !!(rule && rule.requires_import_check),
        warning: isBusiness
          ? 'HÀNG KINH DOANH - cần kiểm tra điều kiện nhập khẩu trước khi nhập kho'
          : (rule ? null : 'Chưa xác định được nhóm khách hàng từ mã kho'),
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
