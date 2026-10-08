const crypto = require('crypto');
const db = require('../config/db');
const { HttpError, asyncHandler, parseId } = require('../utils/http');

const TYPES = ['WAREHOUSE', 'CUSTOMER'];
const clean = (v, max) => (v == null ? null : String(v).trim().slice(0, max) || null);
const SELECT = `SELECT h.*, b.code AS location_code, b.alias AS location_alias FROM holds h LEFT JOIN bin_locations b ON b.id = h.bin_location_id`;

async function locationId(v) {
  if (v === '' || v == null) return null;
  const id = parseId(v, 'Vị trí');
  if (!(await db.query('SELECT 1 FROM bin_locations WHERE id=$1', [id])).rowCount) throw new HttpError(404, 'Không tìm thấy vị trí', 'LOCATION_NOT_FOUND');
  return id;
}

// GET /api/v1/holds?tab=HOLD|BLOCK|DONE&search=&no_location=1&location=ID&from=YYYY-MM-DD&to=YYYY-MM-DD&page=&limit=
// "counts" dem theo cac bo loc khac (tru tab).
exports.list = asyncHandler(async (req, res) => {
  const q = req.query;
  const page = Math.max(1, parseInt(q.page, 10) || 1);
  const limit = Math.min(100, Math.max(1, parseInt(q.limit, 10) || 20));
  const where = [], params = [];
  const add = (sql, v) => { params.push(v); where.push(sql.replaceAll('?', `$${params.length}`)); };
  const s = String(q.search || '').trim();
  if (s) add('(h.tracking_code ILIKE ? OR h.hold_code ILIKE ?)', `%${s}%`);
  if (q.no_location === '1') where.push('h.bin_location_id IS NULL');
  else if (q.location) add('h.bin_location_id = ?', parseId(q.location, 'Vị trí'));
  if (q.from) add('h.opened_at >= ?::date', String(q.from));
  if (q.to) add('h.opened_at < (?::date + 1)', String(q.to));
  const base = where.length ? `WHERE ${where.join(' AND ')}` : '';
  const and = (c) => `${base ? base + ' AND' : 'WHERE'} ${c}`;
  const c = (await db.query(
    `SELECT COUNT(*) FILTER (WHERE h.status='ACTIVE' AND h.hold_type='WAREHOUSE') AS hold,
            COUNT(*) FILTER (WHERE h.status='ACTIVE' AND h.hold_type='CUSTOMER') AS block,
            COUNT(*) FILTER (WHERE h.status='RESOLVED') AS done FROM holds h ${base}`, params)).rows[0];
  const counts = { hold: Number(c.hold), block: Number(c.block), done: Number(c.done) };
  const tab = String(q.tab || 'HOLD').toUpperCase();
  const cond = tab === 'BLOCK' ? "h.status='ACTIVE' AND h.hold_type='CUSTOMER'" : tab === 'DONE' ? "h.status='RESOLVED'" : "h.status='ACTIVE' AND h.hold_type='WAREHOUSE'";
  const total = tab === 'BLOCK' ? counts.block : tab === 'DONE' ? counts.done : counts.hold;
  const { rows } = await db.query(`${SELECT} ${and(cond)} ORDER BY h.opened_at DESC, h.id DESC LIMIT ${limit} OFFSET ${(page - 1) * limit}`, params);
  res.json({ data: rows, counts, pagination: { page, limit, total, total_pages: Math.max(1, Math.ceil(total / limit)) } });
});

// POST /api/v1/holds  { tracking_code, hold_type, reason_code, reason, bin_location_id }
exports.create = asyncHandler(async (req, res) => {
  const b = req.body || {};
  const tracking = clean(b.tracking_code, 100);
  if (!tracking) throw new HttpError(400, 'Vui lòng nhập mã tracking', 'TRACKING_REQUIRED');
  const type = String(b.hold_type || 'WAREHOUSE').toUpperCase();
  if (!TYPES.includes(type)) throw new HttpError(400, 'Loại giữ hàng không hợp lệ', 'INVALID_TYPE');
  const reasonCode = (clean(b.reason_code, 50) || 'OTHER').toUpperCase().replace(/[^A-Z0-9_]/g, '_');
  const loc = await locationId(b.bin_location_id);
  const holdCode = `HOLD-${Date.now()}-${crypto.randomBytes(4).toString('hex')}-${reasonCode}`;
  const { rows } = await db.query(
    `INSERT INTO holds (tracking_code, hold_code, hold_type, reason_code, reason, bin_location_id) VALUES ($1,$2,$3,$4,$5,$6) RETURNING id`,
    [tracking, holdCode, type, reasonCode, clean(b.reason, 300), loc]);
  res.status(201).json({ data: (await db.query(`${SELECT} WHERE h.id=$1`, [rows[0].id])).rows[0] });
});

// PATCH /api/v1/holds/:id  { bin_location_id?, status? ('ACTIVE'|'RESOLVED'), reason? }
exports.patch = asyncHandler(async (req, res) => {
  const id = parseId(req.params.id);
  const b = req.body || {};
  const sets = [], params = [id];
  const set = (col, v) => { params.push(v); sets.push(`${col}=$${params.length}`); };
  if ('bin_location_id' in b) set('bin_location_id', await locationId(b.bin_location_id));
  if ('reason' in b) set('reason', clean(b.reason, 300));
  if ('status' in b) {
    const st = String(b.status).toUpperCase();
    if (!['ACTIVE', 'RESOLVED'].includes(st)) throw new HttpError(400, 'Trạng thái không hợp lệ', 'INVALID_STATUS');
    set('status', st); sets.push(st === 'RESOLVED' ? 'resolved_at=NOW()' : 'resolved_at=NULL');
  }
  if (!sets.length) throw new HttpError(400, 'Không có gì để cập nhật', 'NOTHING');
  const r = await db.query(`UPDATE holds SET ${sets.join(',')} WHERE id=$1`, params);
  if (!r.rowCount) throw new HttpError(404, 'Không tìm thấy hàng giữ', 'HOLD_NOT_FOUND');
  res.json({ data: (await db.query(`${SELECT} WHERE h.id=$1`, [id])).rows[0] });
});

// PATCH /api/v1/holds/bulk  { ids: [...], action: 'assign'|'resolve', bin_location_id }
exports.bulk = asyncHandler(async (req, res) => {
  const ids = (Array.isArray(req.body?.ids) ? req.body.ids : []).map((x) => parseId(x));
  if (!ids.length) throw new HttpError(400, 'Chưa chọn kiện nào', 'EMPTY');
  const action = req.body.action;
  let r;
  if (action === 'resolve') r = await db.query(`UPDATE holds SET status='RESOLVED', resolved_at=NOW() WHERE id = ANY($1)`, [ids]);
  else if (action === 'assign') r = await db.query('UPDATE holds SET bin_location_id=$2 WHERE id = ANY($1)', [ids, await locationId(req.body.bin_location_id)]);
  else throw new HttpError(400, 'Thao tác không hợp lệ', 'INVALID_ACTION');
  res.json({ data: { updated: r.rowCount } });
});

// DELETE /api/v1/holds/:id
exports.remove = asyncHandler(async (req, res) => {
  const id = parseId(req.params.id);
  if (!(await db.query('DELETE FROM holds WHERE id=$1', [id])).rowCount) throw new HttpError(404, 'Không tìm thấy hàng giữ', 'HOLD_NOT_FOUND');
  res.json({ data: { id } });
});
