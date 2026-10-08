const db = require('../config/db');
const { HttpError, asyncHandler, parseId } = require('../utils/http');

const MODES = ['INFORMAL', 'FORMAL'];
const STATUSES = ['OPEN', 'CLOSED', 'ARRIVED'];
// Loai ngay dung de loc khoang ngay (khoa -> cot SQL)
const DATE_FIELDS = { created: 'created_at', etd: 'etd', eta: 'eta' };

const clean = (v, max) => (v == null ? null : String(v).trim().slice(0, max) || null);
const intOr0 = (v, label) => {
  if (v === '' || v == null) return 0;
  const n = Number(v);
  if (!Number.isInteger(n) || n < 0 || n > 1000000) throw new HttpError(400, `${label} phải là số nguyên từ 0 trở lên`, 'INVALID_NUMBER');
  return n;
};
const dateOrNull = (v, label) => {
  if (!v) return null;
  const d = new Date(v);
  if (Number.isNaN(d.getTime())) throw new HttpError(400, `${label} không hợp lệ`, 'INVALID_DATE');
  return v;
};

function readBody(b = {}) {
  const name = clean(b.name, 200);
  if (!name) throw new HttpError(400, 'Vui lòng nhập tên chuyến bay', 'NAME_REQUIRED');
  const mode = String(b.transport_mode || 'INFORMAL').toUpperCase();
  if (!MODES.includes(mode)) throw new HttpError(400, 'Hình thức vận chuyển không hợp lệ', 'INVALID_MODE');
  const etd = dateOrNull(b.etd, 'ETD'), eta = dateOrNull(b.eta, 'ETA');
  if (etd && eta && new Date(eta) < new Date(etd)) throw new HttpError(400, 'ETA phải sau ETD', 'INVALID_DATE_RANGE');
  const up = (v, n) => { const c = clean(v, n); return c ? c.toUpperCase() : null; };
  return {
    name, mawb: clean(b.mawb, 50), airline_code: clean(b.airline_code, 30), airline_name: clean(b.airline_name, 100),
    origin: up(b.origin, 10), destination: up(b.destination, 10), transport_mode: mode, etd, eta,
    box_count: intOr0(b.box_count, 'Số thùng'), hawb_count: intOr0(b.hawb_count, 'Số HAWB'), note: clean(b.note, 500),
  };
}

// GET /api/v1/flights?tab=ALL|OPEN|CLOSED&search=&airline=&mode=&date_field=&from=&to=&origin=&destination=&page=&limit=
// "counts" dem theo cac bo loc khac (tru tab) de hien so tren tab.
exports.list = asyncHandler(async (req, res) => {
  const q = req.query;
  const page = Math.max(1, parseInt(q.page, 10) || 1);
  const limit = Math.min(100, Math.max(1, parseInt(q.limit, 10) || 20));
  const where = [], params = [];
  const add = (sql, v) => { params.push(v); where.push(sql.replaceAll('?', `$${params.length}`)); };

  const s = String(q.search || '').trim();
  if (s) add('(name ILIKE ? OR mawb ILIKE ?)', `%${s}%`);
  if (q.airline) add('airline_code = ?', String(q.airline));
  const mode = String(q.mode || '').toUpperCase();
  if (MODES.includes(mode)) add('transport_mode = ?', mode);
  if (q.origin) add('origin = ?', String(q.origin).toUpperCase());
  if (q.destination) add('destination = ?', String(q.destination).toUpperCase());
  const status = String(q.status || '').toUpperCase();
  if (STATUSES.includes(status)) add('status = ?', status);
  const col = DATE_FIELDS[q.date_field] || DATE_FIELDS.created;
  if (q.from) add(`${col} >= ?::date`, String(q.from));
  if (q.to) add(`${col} < (?::date + 1)`, String(q.to));

  const base = where.length ? `WHERE ${where.join(' AND ')}` : '';
  const cnt = (await db.query(
    `SELECT COUNT(*) AS all, COUNT(*) FILTER (WHERE status='OPEN') AS open, COUNT(*) FILTER (WHERE status<>'OPEN') AS closed
       FROM flights ${base}`, params)).rows[0];
  const counts = { all: Number(cnt.all), open: Number(cnt.open), closed: Number(cnt.closed) };

  const tab = String(q.tab || 'ALL').toUpperCase();
  const w = tab === 'OPEN' ? `${base ? base + ' AND' : 'WHERE'} status = 'OPEN'`
          : tab === 'CLOSED' ? `${base ? base + ' AND' : 'WHERE'} status <> 'OPEN'` : base;
  const total = tab === 'OPEN' ? counts.open : tab === 'CLOSED' ? counts.closed : counts.all;
  const { rows } = await db.query(
    `SELECT * FROM flights ${w} ORDER BY created_at DESC, id DESC LIMIT ${limit} OFFSET ${(page - 1) * limit}`, params);
  res.json({ data: rows, counts, pagination: { page, limit, total, total_pages: Math.max(1, Math.ceil(total / limit)) } });
});

// POST /api/v1/flights
exports.create = asyncHandler(async (req, res) => {
  const d = readBody(req.body);
  const { rows } = await db.query(
    `INSERT INTO flights (name, mawb, airline_code, airline_name, origin, destination, transport_mode, etd, eta, box_count, hawb_count, note)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) RETURNING *`,
    [d.name, d.mawb, d.airline_code, d.airline_name, d.origin, d.destination, d.transport_mode, d.etd, d.eta, d.box_count, d.hawb_count, d.note]);
  res.status(201).json({ data: rows[0] });
});

// PUT /api/v1/flights/:id
exports.update = asyncHandler(async (req, res) => {
  const id = parseId(req.params.id);
  const d = readBody(req.body);
  const { rows } = await db.query(
    `UPDATE flights SET name=$2, mawb=$3, airline_code=$4, airline_name=$5, origin=$6, destination=$7, transport_mode=$8,
            etd=$9, eta=$10, box_count=$11, hawb_count=$12, note=$13 WHERE id=$1 RETURNING *`,
    [id, d.name, d.mawb, d.airline_code, d.airline_name, d.origin, d.destination, d.transport_mode, d.etd, d.eta, d.box_count, d.hawb_count, d.note]);
  if (!rows.length) throw new HttpError(404, 'Không tìm thấy chuyến bay', 'FLIGHT_NOT_FOUND');
  res.json({ data: rows[0] });
});

// PATCH /api/v1/flights/:id/status   { status: 'OPEN' | 'CLOSED' | 'ARRIVED' }
exports.setStatus = asyncHandler(async (req, res) => {
  const id = parseId(req.params.id);
  const status = String(req.body?.status || '').toUpperCase();
  if (!STATUSES.includes(status)) throw new HttpError(400, 'Trạng thái không hợp lệ', 'INVALID_STATUS');
  const { rows } = await db.query('UPDATE flights SET status=$2 WHERE id=$1 RETURNING *', [id, status]);
  if (!rows.length) throw new HttpError(404, 'Không tìm thấy chuyến bay', 'FLIGHT_NOT_FOUND');
  res.json({ data: rows[0] });
});

// DELETE /api/v1/flights/:id  (chi xoa duoc chuyen chua co thung)
exports.remove = asyncHandler(async (req, res) => {
  const id = parseId(req.params.id);
  const cur = await db.query('SELECT box_count FROM flights WHERE id=$1', [id]);
  if (!cur.rows.length) throw new HttpError(404, 'Không tìm thấy chuyến bay', 'FLIGHT_NOT_FOUND');
  if (cur.rows[0].box_count > 0) throw new HttpError(409, 'Chuyến bay đã có thùng, không thể xóa', 'FLIGHT_HAS_BOXES');
  await db.query('DELETE FROM flights WHERE id=$1', [id]);
  res.json({ data: { id } });
});
