// Tien ich HTTP dung chung: loi co ma trang thai + wrapper async
class HttpError extends Error {
  constructor(status, message, code, extra = {}) {
    super(message);
    this.status = status;
    this.code = code;
    this.extra = extra;
  }
}

// Boc handler async de loi tu dong chuyen vao error middleware
const asyncHandler = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

// Parse id so nguyen duong tu params
function parseId(value, label = 'id') {
  const n = Number(value);
  if (!Number.isInteger(n) || n <= 0) throw new HttpError(400, `${label} không hợp lệ`, 'INVALID_ID');
  return n;
}

module.exports = { HttpError, asyncHandler, parseId };
