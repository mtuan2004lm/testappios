const db = require('../config/db');
const { HttpError, asyncHandler, parseId } = require('../utils/http');
const { matchRule } = require('../utils/ruleMatcher');

// POST /api/v1/receiving/sessions/:id/scan   body: { barcode, detected_text, scanned_by? }
exports.scan = asyncHandler(async (req, res) => {
  const sessionId = parseId(req.params.id);
  const barcode = String((req.body && req.body.barcode) || '').trim();
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
    const reg = (await client.query('SELECT warehouse_code FROM tracking_codes WHERE barcode = $1', [barcode])).rows[0];
    const inRegistry = !!reg;
    // App iOS gui mã kho doc duoc tu nhan (detected_text khac barcode) -> uu tien dung, vi la du lieu moi nhat
    const hasExplicitText = detectedText !== barcode;
    const matchText = hasExplicitText ? detectedText : ((reg && reg.warehouse_code) || detectedText);

    // Khop regex voi cac rule dang bat
    const rules = (await client.query('SELECT * FROM warehouse_rules WHERE is_active = TRUE ORDER BY id')).rows;
    const rule = matchRule(matchText, rules);

    // ON CONFLICT bat loi trung (session_id, barcode) ma khong lam hong transaction
    const ins = await client.query(
      `INSERT INTO scanned_items
         (session_id, barcode, detected_warehouse_code, matched_rule_id, customer_group, business_type, exception_status, scanned_by)
       VALUES ($1, $2, $3, $4, $5, $6, $7, COALESCE($8, 'Nhan vien 01'))
       ON CONFLICT ON CONSTRAINT unique_barcode_per_session DO NOTHING
       RETURNING *`,
      [sessionId, barcode, matchText, rule ? rule.id : null, rule ? rule.customer_group : null,
       rule ? rule.business_type : null,
       // Co trong danh sach tracking, hoac duoc nhan dien tu ma kho in tren nhan -> binh thuong; con lai -> UNKNOWN
       (inRegistry || (hasExplicitText && rule)) ? 'NORMAL' : 'UNKNOWN', scannedBy]
    );

    if (!ins.rows.length) {
      // Ma da quet trong phien nay -> tang bo dem trung, tra 409
      const up = await client.query(
        'UPDATE receiving_sessions SET duplicate_count = duplicate_count + 1 WHERE id = $1 RETURNING duplicate_count', [sessionId]);
      await client.query('COMMIT');
      return res.status(409).json({
        error: { code: 'DUPLICATE_BARCODE', message: `Mã ${barcode} đã được quét trong phiên này` },
        data: { barcode, exception_status: 'DUPLICATE', duplicate_count: up.rows[0].duplicate_count },
      });
    }

    const up = await client.query(
      'UPDATE receiving_sessions SET scanned_count = scanned_count + 1 WHERE id = $1 RETURNING scanned_count, total_expected_packages', [sessionId]);
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
          : (!inRegistry && !(hasExplicitText && rule) ? 'Mã chưa có trong danh sách tracking'
            : (rule ? null : 'Chưa xác định được nhóm khách hàng từ mã kho')),
      },
    });
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
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
