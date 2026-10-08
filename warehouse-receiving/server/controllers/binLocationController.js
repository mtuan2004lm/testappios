const db = require('../config/db');
const { HttpError, asyncHandler, parseId } = require('../utils/http');

const PARTS = ['zone', 'subzone', 'aisle', 'rack', 'level', 'cell']; // Khu, Tieu khu, Loi, Gia, Tang, O
const clean = (v, max) => (v == null ? null : String(v).trim().slice(0, max) || null);

// Doc cac o + ghep thanh ma vi tri (chi ghep cac o da dien)
function readParts(b = {}) {
  const p = {};
  for (const k of PARTS) p[k] = clean(b[k], 20);
  const code = PARTS.map((k) => p[k]).filter(Boolean).join('-');
  if (!code) throw new HttpError(400, 'Điền ít nhất một ô để tạo mã vị trí', 'LOCATION_EMPTY');
  return { ...p, code, alias: clean(b.alias, 100) };
}
const COLS = [...PARTS, 'code', 'alias'];
const insertSql = `INSERT INTO bin_locations (${COLS.join(',')}) VALUES (${COLS.map((_, i) => `$${i + 1}`).join(',')})`;
const vals = (d) => COLS.map((k) => d[k]);

// GET /api/v1/bin-locations?search=
exports.list = asyncHandler(async (req, res) => {
  const q = String(req.query.search || '').trim();
  const { rows } = q
    ? await db.query('SELECT * FROM bin_locations WHERE code ILIKE $1 OR alias ILIKE $1 ORDER BY code', [`%${q}%`])
    : await db.query('SELECT * FROM bin_locations ORDER BY code');
  const total = Number((await db.query('SELECT COUNT(*) FROM bin_locations')).rows[0].count);
  res.json({ data: rows, total });
});

// POST /api/v1/bin-locations
exports.create = asyncHandler(async (req, res) => {
  const d = readParts(req.body);
  if ((await db.query('SELECT 1 FROM bin_locations WHERE code = $1', [d.code])).rowCount)
    throw new HttpError(409, `Mã vị trí ${d.code} đã tồn tại`, 'LOCATION_EXISTS');
  const { rows } = await db.query(`${insertSql} RETURNING *`, vals(d));
  res.status(201).json({ data: rows[0] });
});

// POST /api/v1/bin-locations/bulk   { items: [{zone, rack, ...}, ...] }  -> bo qua ma da ton tai
exports.bulk = asyncHandler(async (req, res) => {
  const items = Array.isArray(req.body?.items) ? req.body.items : [];
  if (!items.length) throw new HttpError(400, 'Không có vị trí nào để thêm', 'EMPTY');
  if (items.length > 1000) throw new HttpError(400, 'Tối đa 1000 vị trí mỗi lần', 'TOO_MANY');
  let created = 0, skipped = 0;
  const client = await db.pool.connect();
  try {
    await client.query('BEGIN');
    for (const it of items) {
      const d = readParts(it);
      const r = await client.query(`${insertSql} ON CONFLICT (code) DO NOTHING`, vals(d));
      r.rowCount ? created++ : skipped++;
    }
    await client.query('COMMIT');
  } catch (e) { await client.query('ROLLBACK'); throw e; } finally { client.release(); }
  res.status(201).json({ data: { created, skipped } });
});

// PUT /api/v1/bin-locations/:id
exports.update = asyncHandler(async (req, res) => {
  const id = parseId(req.params.id);
  const d = readParts(req.body);
  if ((await db.query('SELECT 1 FROM bin_locations WHERE code = $1 AND id <> $2', [d.code, id])).rowCount)
    throw new HttpError(409, `Mã vị trí ${d.code} đã tồn tại`, 'LOCATION_EXISTS');
  const { rows } = await db.query(
    `UPDATE bin_locations SET ${COLS.map((k, i) => `${k}=$${i + 2}`).join(',')} WHERE id=$1 RETURNING *`, [id, ...vals(d)]);
  if (!rows.length) throw new HttpError(404, 'Không tìm thấy vị trí', 'LOCATION_NOT_FOUND');
  res.json({ data: rows[0] });
});

// DELETE /api/v1/bin-locations/:id  (hang dang giu o vi tri nay se thanh "chua co vi tri")
exports.remove = asyncHandler(async (req, res) => {
  const id = parseId(req.params.id);
  const { rowCount } = await db.query('DELETE FROM bin_locations WHERE id = $1', [id]);
  if (!rowCount) throw new HttpError(404, 'Không tìm thấy vị trí', 'LOCATION_NOT_FOUND');
  res.json({ data: { id } });
});
