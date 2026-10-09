const db = require('../config/db');
const { HttpError, asyncHandler, parseId } = require('../utils/http');
const { matchProduct } = require('../utils/trackingFormats');

const MODES = ['FULL', 'LAST', 'DROP_FIRST', 'REGEX'];
const clean = (v, max) => (v == null ? null : String(v).trim().slice(0, max) || null);

function readBody(b = {}) {
  const carrier = (clean(b.carrier, 30) || '').toUpperCase();
  const name = clean(b.name, 100);
  const detect = clean(b.detect_regex, 200);
  if (!carrier) throw new HttpError(400, 'Vui lòng nhập hãng (USPS, UPS, FEDEX…)', 'CARRIER_REQUIRED');
  if (!name) throw new HttpError(400, 'Vui lòng nhập tên định dạng', 'NAME_REQUIRED');
  if (!detect) throw new HttpError(400, 'Vui lòng nhập biểu thức nhận biết (regex)', 'DETECT_REQUIRED');
  try { new RegExp(detect); } catch (e) { throw new HttpError(400, `Regex nhận biết sai: ${e.message}`, 'INVALID_REGEX'); }
  const mode = String(b.extract_mode || 'FULL').toUpperCase();
  if (!MODES.includes(mode)) throw new HttpError(400, 'Cách rút mã không hợp lệ', 'INVALID_MODE');
  const param = clean(b.extract_param, 200);
  if (mode === 'REGEX') { try { new RegExp(param || ''); } catch (e) { throw new HttpError(400, `Regex rút mã sai: ${e.message}`, 'INVALID_REGEX'); } }
  if ((mode === 'LAST' || mode === 'DROP_FIRST') && !(parseInt(param, 10) > 0)) throw new HttpError(400, 'Cần nhập số ký tự (số nguyên dương)', 'INVALID_PARAM');
  const sort = Number.isInteger(Number(b.sort_order)) ? Number(b.sort_order) : 100;
  return { carrier, name, detect, mode, param, active: b.is_active !== false, sort };
}

// GET /api/v1/tracking-formats
exports.list = asyncHandler(async (req, res) => {
  res.json({ data: (await db.query('SELECT * FROM tracking_formats ORDER BY sort_order, id')).rows });
});

// POST /api/v1/tracking-formats
exports.create = asyncHandler(async (req, res) => {
  const d = readBody(req.body);
  if ((await db.query('SELECT 1 FROM tracking_formats WHERE name = $1', [d.name])).rowCount) throw new HttpError(409, 'Tên định dạng đã tồn tại', 'FORMAT_EXISTS');
  const { rows } = await db.query(
    `INSERT INTO tracking_formats (carrier, name, detect_regex, extract_mode, extract_param, is_active, sort_order) VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING *`,
    [d.carrier, d.name, d.detect, d.mode, d.param, d.active, d.sort]);
  res.status(201).json({ data: rows[0] });
});

// PUT /api/v1/tracking-formats/:id
exports.update = asyncHandler(async (req, res) => {
  const id = parseId(req.params.id);
  const d = readBody(req.body);
  if ((await db.query('SELECT 1 FROM tracking_formats WHERE name = $1 AND id <> $2', [d.name, id])).rowCount) throw new HttpError(409, 'Tên định dạng đã tồn tại', 'FORMAT_EXISTS');
  const { rows } = await db.query(
    `UPDATE tracking_formats SET carrier=$2, name=$3, detect_regex=$4, extract_mode=$5, extract_param=$6, is_active=$7, sort_order=$8 WHERE id=$1 RETURNING *`,
    [id, d.carrier, d.name, d.detect, d.mode, d.param, d.active, d.sort]);
  if (!rows.length) throw new HttpError(404, 'Không tìm thấy định dạng', 'FORMAT_NOT_FOUND');
  res.json({ data: rows[0] });
});

// DELETE /api/v1/tracking-formats/:id
exports.remove = asyncHandler(async (req, res) => {
  const id = parseId(req.params.id);
  if (!(await db.query('DELETE FROM tracking_formats WHERE id=$1', [id])).rowCount) throw new HttpError(404, 'Không tìm thấy định dạng', 'FORMAT_NOT_FOUND');
  res.json({ data: { id } });
});

// POST /api/v1/tracking-formats/test  { barcode, carrier_name? }  -> thu doi chieu, khong ghi gi
exports.test = asyncHandler(async (req, res) => {
  const barcode = String(req.body?.barcode || '').trim();
  if (!barcode) throw new HttpError(400, 'Vui lòng nhập mã vạch', 'BARCODE_REQUIRED');
  const m = await matchProduct(db, barcode, req.body?.carrier_name);
  res.json({ data: {
    normalized: m.code, carrier: m.carrier, method: m.method, candidates: m.candidates,
    product: m.product ? { id: m.product.id, name: m.product.name, tracking_code: m.product.tracking_code, alt_code: m.product.alt_code, alt_code2: m.product.alt_code2 } : null,
  } });
});
