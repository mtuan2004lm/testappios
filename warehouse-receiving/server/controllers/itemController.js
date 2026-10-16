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

// POST /api/v1/scanned-items/:id/label-photo   (body: anh JPEG/PNG tho)
// Anh label cua kien (de nhan vien VN doc thong tin tren label, kiem duyet va cap nhat cho khach). Khong doi trang thai kien.
exports.addLabelPhoto = asyncHandler(async (req, res) => {
  const id = parseId(req.params.id);
  if (!Buffer.isBuffer(req.body) || !req.body.length) throw new HttpError(400, 'Thiếu dữ liệu ảnh (Content-Type: image/jpeg)', 'PHOTO_REQUIRED');
  const exists = await db.query('SELECT 1 FROM scanned_items WHERE id = $1', [id]);
  if (!exists.rows.length) throw new HttpError(404, 'Không tìm thấy kiện hàng', 'ITEM_NOT_FOUND');
  const ext = /png/i.test(req.headers['content-type'] || '') ? 'png' : 'jpg';
  fs.mkdirSync(UPLOAD_DIR, { recursive: true });
  const file = `label-${id}-${Date.now()}.${ext}`;
  fs.writeFileSync(path.join(UPLOAD_DIR, file), req.body);
  const urlPath = `/uploads/${file}`;
  await db.query(`INSERT INTO item_photos (item_id, file_path, kind) VALUES ($1, $2, 'LABEL')`, [id, urlPath]);
  const { rows } = await db.query('SELECT * FROM scanned_items WHERE id = $1', [id]);
  res.status(201).json({ data: { item: rows[0], photo_url: urlPath } });
});

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

// POST /api/v1/receiving/sessions/:id/items/delete   body: { ids: [1,2,3] }
// Xoa cac kien da chon trong MOT phien dang mo (vd kien nhap tay / quet thu). Xoa luon anh + cac dong quet tem
// cua kien do (neu khong, cac tracking se bi coi la "dang cho" va dinh vao kien ke tiep). Tinh lai scanned_count.
exports.deleteItems = asyncHandler(async (req, res) => {
  const sessionId = parseId(req.params.id);
  const ids = Array.isArray(req.body && req.body.ids) ? [...new Set(req.body.ids.map((x) => Number(x)))] : [];
  if (!ids.length || ids.length > 500 || ids.some((x) => !Number.isInteger(x) || x <= 0)) {
    throw new HttpError(400, 'ids phải là danh sách 1–500 số nguyên', 'INVALID_IDS');
  }
  const client = await db.getClient();
  let files = [];
  try {
    await client.query('BEGIN');
    const s = await client.query('SELECT status FROM receiving_sessions WHERE id = $1 FOR UPDATE', [sessionId]);
    if (!s.rows.length) throw new HttpError(404, 'Không tìm thấy phiên', 'SESSION_NOT_FOUND');
    if (s.rows[0].status !== 'OPEN') throw new HttpError(409, 'Phiên đã đóng, không thể xoá kiện', 'SESSION_CLOSED');
    const own = (await client.query('SELECT id FROM scanned_items WHERE session_id = $1 AND id = ANY($2::bigint[])', [sessionId, ids])).rows.map((r) => r.id);
    if (!own.length) throw new HttpError(404, 'Không tìm thấy kiện nào để xoá trong phiên này', 'ITEM_NOT_FOUND');
    files = (await client.query('SELECT file_path FROM item_photos WHERE item_id = ANY($1::bigint[])', [own])).rows.map((r) => r.file_path);
    await client.query('DELETE FROM label_scans WHERE item_id = ANY($1::bigint[])', [own]);
    await client.query('DELETE FROM scanned_items WHERE id = ANY($1::bigint[])', [own]);
    const up = await client.query(
      `UPDATE receiving_sessions SET scanned_count = (SELECT COUNT(*) FROM scanned_items WHERE session_id = $1) WHERE id = $1 RETURNING scanned_count`, [sessionId]);
    await client.query('COMMIT');
    for (const f of files) { try { fs.unlinkSync(path.join(UPLOAD_DIR, path.basename(f))); } catch (e) { /* file da mat thi bo qua */ } }
    res.json({ data: { deleted: own.length, deleted_ids: own, scanned_count: up.rows[0].scanned_count } });
  } catch (e) {
    await client.query('ROLLBACK').catch(() => {});
    throw e;
  } finally {
    client.release();
  }
});
