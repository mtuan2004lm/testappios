const fs = require('fs');
const path = require('path');
const db = require('../config/db');
const { HttpError, asyncHandler, parseId } = require('../utils/http');

// PATCH /api/v1/scanned-items/:id/toggle-business-type
// Doi thu cong KINH_DOANH <-> KHONG_KINH_DOANH (vd: khong du dieu kien nhap khau)
exports.toggleBusinessType = asyncHandler(async (req, res) => {
  const id = parseId(req.params.id);
  const { rows } = await db.query(
    `UPDATE scanned_items
        SET business_type = CASE business_type
              WHEN 'KINH_DOANH' THEN 'KHONG_KINH_DOANH'::business_type_enum
              WHEN 'KHONG_KINH_DOANH' THEN 'KINH_DOANH'::business_type_enum
            END
      WHERE id = $1 AND business_type IS NOT NULL
      RETURNING *`, [id]);
  if (!rows.length) {
    const exists = await db.query('SELECT 1 FROM scanned_items WHERE id = $1', [id]);
    if (!exists.rows.length) throw new HttpError(404, 'Không tìm thấy kiện hàng', 'ITEM_NOT_FOUND');
    throw new HttpError(409, 'Kiện chưa có loại hình kinh doanh để chuyển đổi', 'NO_BUSINESS_TYPE');
  }
  res.json({ data: rows[0] });
});

// PATCH /api/v1/scanned-items/:id/exception   body: { exception_status }
// Danh dau ngoai le: NORMAL | UNKNOWN | DAMAGED | HOLDING | BLOCKED
exports.setException = asyncHandler(async (req, res) => {
  const id = parseId(req.params.id);
  const status = String((req.body && req.body.exception_status) || '').toUpperCase();
  if (!['NORMAL', 'UNKNOWN', 'DAMAGED', 'HOLDING', 'BLOCKED'].includes(status))
    throw new HttpError(400, 'exception_status không hợp lệ', 'INVALID_EXCEPTION');
  const { rows } = await db.query('UPDATE scanned_items SET exception_status = $2 WHERE id = $1 RETURNING *', [id, status]);
  if (!rows.length) throw new HttpError(404, 'Không tìm thấy kiện hàng', 'ITEM_NOT_FOUND');
  res.json({ data: rows[0] });
});

const UPLOAD_DIR = path.join(__dirname, '..', 'uploads');

// POST /api/v1/scanned-items/:id/damage-photo   (body: anh JPEG/PNG tho, Content-Type: image/jpeg)
// Gan anh vao kien va danh dau DAMAGED
exports.addDamagePhoto = asyncHandler(async (req, res) => {
  const id = parseId(req.params.id);
  if (!Buffer.isBuffer(req.body) || !req.body.length) throw new HttpError(400, 'Thiếu dữ liệu ảnh (Content-Type: image/jpeg)', 'PHOTO_REQUIRED');
  const exists = await db.query('SELECT 1 FROM scanned_items WHERE id = $1', [id]);
  if (!exists.rows.length) throw new HttpError(404, 'Không tìm thấy kiện hàng', 'ITEM_NOT_FOUND');

  const ext = /png/i.test(req.headers['content-type'] || '') ? 'png' : 'jpg';
  fs.mkdirSync(UPLOAD_DIR, { recursive: true });
  const file = `item-${id}-${Date.now()}.${ext}`;
  fs.writeFileSync(path.join(UPLOAD_DIR, file), req.body);

  const urlPath = `/uploads/${file}`;
  await db.query('INSERT INTO item_photos (item_id, file_path) VALUES ($1, $2)', [id, urlPath]);
  const { rows } = await db.query(`UPDATE scanned_items SET exception_status = 'DAMAGED' WHERE id = $1 RETURNING *`, [id]);
  res.status(201).json({ data: { item: rows[0], photo_url: urlPath } });
});
