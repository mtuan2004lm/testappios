const fs = require('fs');
const path = require('path');
const db = require('../config/db');
const { HttpError, asyncHandler, parseId } = require('../utils/http');

const UPLOAD_DIR = path.join(__dirname, '..', 'uploads');
const FILTERS = ['UNFILTERED', 'FILTERED'];
// Cot cho phep tim kiem (khoa -> cot SQL)
const SEARCH_FIELDS = { tracking: 'tracking_code', order: 'order_code', name: 'name', partner: 'partner_name' };

const clean = (v, max) => (v == null ? null : String(v).trim().slice(0, max) || null);

// Doc + kiem tra du lieu form (dung chung cho tao / sua)
function readBody(body = {}) {
  const name = clean(body.name, 300);
  const tracking = clean(body.tracking_code, 100);
  if (!name) throw new HttpError(400, 'Vui lòng nhập tên hàng', 'NAME_REQUIRED');
  if (!tracking) throw new HttpError(400, 'Vui lòng nhập mã tracking', 'TRACKING_REQUIRED');
  const quantity = body.quantity === '' || body.quantity == null ? 1 : Number(body.quantity);
  if (!Number.isInteger(quantity) || quantity < 1 || quantity > 100000)
    throw new HttpError(400, 'Số lượng phải là số nguyên từ 1 trở lên', 'INVALID_QUANTITY');
  const filter = String(body.filter_status || 'UNFILTERED').toUpperCase();
  if (!FILTERS.includes(filter)) throw new HttpError(400, 'Trạng thái dịch lọc không hợp lệ', 'INVALID_FILTER');
  return {
    name, tracking_code: tracking, quantity, filter_status: filter,
    alt_code: clean(body.alt_code, 100), order_code: clean(body.order_code, 100),
    partner_name: clean(body.partner_name, 100), partner_note: clean(body.partner_note, 200),
  };
}

// GET /api/v1/products?filter=UNFILTERED|FILTERED&field=tracking&search=...&page=&limit=
exports.list = asyncHandler(async (req, res) => {
  const page = Math.max(1, parseInt(req.query.page, 10) || 1);
  const limit = Math.min(100, Math.max(1, parseInt(req.query.limit, 10) || 20));
  const where = [], params = [];
  const filter = String(req.query.filter || '').toUpperCase();
  if (FILTERS.includes(filter)) { params.push(filter); where.push(`filter_status = $${params.length}`); }
  const q = String(req.query.search || '').trim();
  if (q) {
    const col = SEARCH_FIELDS[req.query.field] || SEARCH_FIELDS.tracking;
    params.push(`%${q}%`);
    // Tim theo tracking thi tim ca "Ma khac"
    where.push(col === 'tracking_code' ? `(tracking_code ILIKE $${params.length} OR alt_code ILIKE $${params.length})` : `${col} ILIKE $${params.length}`);
  }
  const w = where.length ? `WHERE ${where.join(' AND ')}` : '';
  const total = Number((await db.query(`SELECT COUNT(*) FROM products ${w}`, params)).rows[0].count);
  const { rows } = await db.query(
    `SELECT * FROM products ${w} ORDER BY id ASC LIMIT ${limit} OFFSET ${(page - 1) * limit}`, params);
  res.json({ data: rows, pagination: { page, limit, total, total_pages: Math.max(1, Math.ceil(total / limit)) } });
});

// POST /api/v1/products
exports.create = asyncHandler(async (req, res) => {
  const d = readBody(req.body);
  const { rows } = await db.query(
    `INSERT INTO products (name, quantity, filter_status, tracking_code, alt_code, order_code, partner_name, partner_note)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8) RETURNING *`,
    [d.name, d.quantity, d.filter_status, d.tracking_code, d.alt_code, d.order_code, d.partner_name, d.partner_note]);
  res.status(201).json({ data: rows[0] });
});

// PUT /api/v1/products/:id
exports.update = asyncHandler(async (req, res) => {
  const id = parseId(req.params.id);
  const d = readBody(req.body);
  const { rows } = await db.query(
    `UPDATE products SET name=$2, quantity=$3, filter_status=$4, tracking_code=$5, alt_code=$6,
            order_code=$7, partner_name=$8, partner_note=$9 WHERE id=$1 RETURNING *`,
    [id, d.name, d.quantity, d.filter_status, d.tracking_code, d.alt_code, d.order_code, d.partner_name, d.partner_note]);
  if (!rows.length) throw new HttpError(404, 'Không tìm thấy mặt hàng', 'PRODUCT_NOT_FOUND');
  res.json({ data: rows[0] });
});

function removeFile(urlPath) {
  if (!urlPath || !urlPath.startsWith('/uploads/')) return;
  fs.promises.unlink(path.join(UPLOAD_DIR, path.basename(urlPath))).catch(() => {});
}

// DELETE /api/v1/products/:id
exports.remove = asyncHandler(async (req, res) => {
  const id = parseId(req.params.id);
  const { rows } = await db.query('DELETE FROM products WHERE id = $1 RETURNING image_path', [id]);
  if (!rows.length) throw new HttpError(404, 'Không tìm thấy mặt hàng', 'PRODUCT_NOT_FOUND');
  removeFile(rows[0].image_path);
  res.json({ data: { id } });
});

// POST /api/v1/products/:id/image   (body: anh tho, Content-Type: image/jpeg|png|webp)
exports.setImage = asyncHandler(async (req, res) => {
  const id = parseId(req.params.id);
  if (!Buffer.isBuffer(req.body) || !req.body.length) throw new HttpError(400, 'Thiếu dữ liệu ảnh', 'PHOTO_REQUIRED');
  const cur = await db.query('SELECT image_path FROM products WHERE id = $1', [id]);
  if (!cur.rows.length) throw new HttpError(404, 'Không tìm thấy mặt hàng', 'PRODUCT_NOT_FOUND');
  const type = req.headers['content-type'] || '';
  const ext = /png/i.test(type) ? 'png' : /webp/i.test(type) ? 'webp' : 'jpg';
  fs.mkdirSync(UPLOAD_DIR, { recursive: true });
  const file = `product-${id}-${Date.now()}.${ext}`;
  fs.writeFileSync(path.join(UPLOAD_DIR, file), req.body);
  const urlPath = `/uploads/${file}`;
  const { rows } = await db.query('UPDATE products SET image_path = $2 WHERE id = $1 RETURNING *', [id, urlPath]);
  removeFile(cur.rows[0].image_path);
  res.json({ data: rows[0] });
});

// DELETE /api/v1/products/:id/image
exports.removeImage = asyncHandler(async (req, res) => {
  const id = parseId(req.params.id);
  const cur = await db.query('SELECT image_path FROM products WHERE id = $1', [id]);
  if (!cur.rows.length) throw new HttpError(404, 'Không tìm thấy mặt hàng', 'PRODUCT_NOT_FOUND');
  const { rows } = await db.query('UPDATE products SET image_path = NULL WHERE id = $1 RETURNING *', [id]);
  removeFile(cur.rows[0].image_path);
  res.json({ data: rows[0] });
});
