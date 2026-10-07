const db = require('../config/db');
const { HttpError, asyncHandler, parseId } = require('../utils/http');

const MAX_BULK = 5000;

// Chen/cap nhat nhieu ma. items: [{ barcode, warehouse_code? }]
// Tra ve { inserted, updated }. Ma da co thi chi cap nhat warehouse_code neu gia tri moi khong rong.
async function bulkUpsert(items) {
  const map = new Map(); // khu trung trong cung request
  for (const it of items) {
    const barcode = String((it && it.barcode) || '').trim();
    if (!barcode || barcode.length > 100) continue;
    const wc = String((it && it.warehouse_code) || '').trim().slice(0, 100) || null;
    map.set(barcode, wc || map.get(barcode) || null);
  }
  if (!map.size) return { inserted: 0, updated: 0 };
  const barcodes = [...map.keys()];
  const codes = barcodes.map((b) => map.get(b));
  const { rows } = await db.query(
    `INSERT INTO tracking_codes (barcode, warehouse_code)
     SELECT * FROM unnest($1::text[], $2::text[])
     ON CONFLICT (barcode) DO UPDATE
       SET warehouse_code = COALESCE(EXCLUDED.warehouse_code, tracking_codes.warehouse_code)
     RETURNING (xmax = 0) AS inserted`,
    [barcodes, codes]
  );
  const inserted = rows.filter((r) => r.inserted).length;
  return { inserted, updated: rows.length - inserted };
}

// GET /api/v1/tracking-codes?search=&page=&limit=
exports.list = asyncHandler(async (req, res) => {
  const page = Math.max(parseInt(req.query.page, 10) || 1, 1);
  const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 20, 1), 200);
  const params = [];
  let where = '';
  if (req.query.search) {
    params.push(`%${String(req.query.search).trim()}%`);
    where = 'WHERE barcode ILIKE $1 OR warehouse_code ILIKE $1';
  }
  const total = Number((await db.query(`SELECT COUNT(*) FROM tracking_codes ${where}`, params)).rows[0].count);
  const { rows } = await db.query(
    `SELECT * FROM tracking_codes ${where} ORDER BY id DESC LIMIT ${limit} OFFSET ${(page - 1) * limit}`, params);
  res.json({ data: rows, pagination: { page, limit, total, total_pages: Math.max(Math.ceil(total / limit), 1) } });
});

// POST /api/v1/tracking-codes/bulk   body: { items: [{ barcode, warehouse_code? }] }
exports.bulk = asyncHandler(async (req, res) => {
  const items = req.body && req.body.items;
  if (!Array.isArray(items) || !items.length) throw new HttpError(400, 'items phải là mảng không rỗng', 'ITEMS_REQUIRED');
  if (items.length > MAX_BULK) throw new HttpError(400, `Tối đa ${MAX_BULK} mã mỗi lần nhập`, 'TOO_MANY');
  const result = await bulkUpsert(items);
  res.status(201).json({ data: { received: items.length, ...result } });
});

// Mau ma kho cho tung nhom khach de ma mau khop dung rule co san
const SAMPLE_WAREHOUSE_CODES = ['SGVO_', 'CHHEN_', 'MCF', 'FDVAT HUE'];

// POST /api/v1/tracking-codes/generate   body: { count } -> tao ma mau de test quet
exports.generate = asyncHandler(async (req, res) => {
  const count = Math.min(Math.max(parseInt(req.body && req.body.count, 10) || 20, 1), 200);
  const items = [];
  for (let i = 0; i < count; i++) {
    const barcode = 'TINA' + String(Math.floor(Math.random() * 1e8)).padStart(8, '0');
    const prefix = SAMPLE_WAREHOUSE_CODES[i % SAMPLE_WAREHOUSE_CODES.length];
    const n = String(Math.floor(Math.random() * 9000) + 1000);
    // MICAFI khop khi ket thuc bang MCF; cac nhom con lai khop o dau chuoi
    const warehouse_code = prefix === 'MCF' ? 'SG HUE MCF' : prefix === 'FDVAT HUE' ? `${prefix} ${n}` : `${prefix}${n}`;
    items.push({ barcode, warehouse_code });
  }
  const result = await bulkUpsert(items);
  res.status(201).json({ data: { requested: count, ...result } });
});

// DELETE /api/v1/tracking-codes/:id
exports.remove = asyncHandler(async (req, res) => {
  const id = parseId(req.params.id);
  const r = await db.query('DELETE FROM tracking_codes WHERE id = $1', [id]);
  if (!r.rowCount) throw new HttpError(404, 'Không tìm thấy mã tracking', 'TRACKING_NOT_FOUND');
  res.status(204).end();
});
