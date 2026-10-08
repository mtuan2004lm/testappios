const db = require('../config/db');
const { HttpError, asyncHandler, parseId } = require('../utils/http');

const EXCEPTION_KEYS = ['UNKNOWN', 'DAMAGED', 'HOLDING', 'BLOCKED'];

// GET /api/v1/receiving/sessions?page=&limit=&status=&carrier=&date=YYYY-MM-DD
exports.listSessions = asyncHandler(async (req, res) => {
  const page = Math.max(parseInt(req.query.page, 10) || 1, 1);
  const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 10, 1), 100);
  const where = [];
  const params = [];

  if (req.query.status) {
    const status = String(req.query.status).toUpperCase();
    if (!['OPEN', 'CLOSED'].includes(status)) throw new HttpError(400, 'status phải là OPEN hoặc CLOSED', 'INVALID_STATUS');
    params.push(status);
    where.push(`status = $${params.length}`);
  }
  if (req.query.carrier) {
    params.push(String(req.query.carrier));
    where.push(`LOWER(carrier_name) = LOWER($${params.length})`);
  }
  if (req.query.date) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(req.query.date)) throw new HttpError(400, 'date phải có dạng YYYY-MM-DD', 'INVALID_DATE');
    params.push(req.query.date);
    where.push(`arrival_time >= $${params.length}::date AND arrival_time < ($${params.length}::date + INTERVAL '1 day')`);
  }
  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';

  const total = Number((await db.query(`SELECT COUNT(*) FROM receiving_sessions ${whereSql}`, params)).rows[0].count);
  const { rows } = await db.query(
    `SELECT * FROM receiving_sessions ${whereSql}
      ORDER BY (status = 'OPEN') DESC, arrival_time DESC, id DESC
      LIMIT ${limit} OFFSET ${(page - 1) * limit}`,
    params
  );

  res.json({ data: rows, pagination: { page, limit, total, total_pages: Math.max(Math.ceil(total / limit), 1) } });
});

// POST /api/v1/receiving/sessions
exports.createSession = asyncHandler(async (req, res) => {
  const b = req.body || {};
  const carrier = String(b.carrier_name || '').trim();
  if (!carrier) throw new HttpError(400, 'carrier_name là bắt buộc', 'CARRIER_REQUIRED');
  const expected = b.total_expected_packages === undefined ? 0 : Number(b.total_expected_packages);
  if (!Number.isInteger(expected) || expected < 0) throw new HttpError(400, 'total_expected_packages phải là số nguyên >= 0', 'INVALID_EXPECTED');

  const { rows } = await db.query(
    `INSERT INTO receiving_sessions (carrier_name, driver_name, license_plate, gate_code, opened_by, total_expected_packages)
     VALUES ($1, $2, $3, COALESCE($4, 'OR_1 - D2'), COALESCE($5, 'Nhan vien 01'), $6)
     RETURNING *`,
    [carrier, b.driver_name || null, b.license_plate || null, b.gate_code || null, b.opened_by || null, expected]
  );
  res.status(201).json({ data: rows[0] });
});

// GET /api/v1/receiving/sessions/:id - thong tin phien + cac kien da quet + dem ngoai le
exports.getSession = asyncHandler(async (req, res) => {
  const id = parseId(req.params.id);
  const s = await db.query('SELECT * FROM receiving_sessions WHERE id = $1', [id]);
  if (!s.rows.length) throw new HttpError(404, 'Không tìm thấy phiên', 'SESSION_NOT_FOUND');
  const session = s.rows[0];

  const items = await db.query(
    `SELECT i.*, COALESCE((SELECT json_agg(p.file_path ORDER BY p.id) FROM item_photos p WHERE p.item_id = i.id), '[]'::json) AS photo_urls
       FROM scanned_items i WHERE i.session_id = $1 ORDER BY i.scanned_at DESC, i.id DESC`, [id]);

  const exceptionCounts = Object.fromEntries(EXCEPTION_KEYS.map((k) => [k, 0]));
  for (const it of items.rows) if (exceptionCounts[it.exception_status] !== undefined) exceptionCounts[it.exception_status] += 1;
  exceptionCounts.FAIL = session.fail_count;           // nhan khong doc duoc barcode (chi co ma kho)
  exceptionCounts.DUPLICATE = session.duplicate_count; // ma trung khong luu thanh dong, dem rieng tren phien

  res.json({ data: { session, items: items.rows, exception_counts: exceptionCounts } });
});

// PATCH /api/v1/receiving/sessions/:id/finalize - "Chot kien": chot tong so kien du kien = so da quet
exports.finalizeCount = asyncHandler(async (req, res) => {
  const id = parseId(req.params.id);
  const { rows } = await db.query(
    `UPDATE receiving_sessions SET total_expected_packages = scanned_count
      WHERE id = $1 AND status = 'OPEN' RETURNING *`, [id]);
  if (!rows.length) throw new HttpError(409, 'Phiên không tồn tại hoặc đã đóng', 'SESSION_NOT_OPEN');
  res.json({ data: rows[0] });
});

// PATCH /api/v1/receiving/sessions/:id/close - ket thuc phien
exports.closeSession = asyncHandler(async (req, res) => {
  const id = parseId(req.params.id);
  const { rows } = await db.query(
    `UPDATE receiving_sessions SET status = 'CLOSED', departure_time = CURRENT_TIMESTAMP
      WHERE id = $1 AND status = 'OPEN' RETURNING *`, [id]);
  if (!rows.length) throw new HttpError(409, 'Phiên không tồn tại hoặc đã đóng', 'SESSION_NOT_OPEN');
  res.json({ data: rows[0] });
});

// PATCH /api/v1/receiving/sessions/:id   body: { total_expected_packages }
// Nhap tay / sua so kien du kien cua phien dang mo
exports.updateExpected = asyncHandler(async (req, res) => {
  const id = parseId(req.params.id);
  const n = Number(req.body && req.body.total_expected_packages);
  if (!Number.isInteger(n) || n < 0 || n > 100000) throw new HttpError(400, 'Số kiện phải là số nguyên từ 0 đến 100000', 'INVALID_EXPECTED');
  const { rows } = await db.query(
    `UPDATE receiving_sessions SET total_expected_packages = $2 WHERE id = $1 AND status = 'OPEN' RETURNING *`, [id, n]);
  if (!rows.length) throw new HttpError(409, 'Phiên không tồn tại hoặc đã đóng', 'SESSION_NOT_OPEN');
  res.json({ data: rows[0] });
});
