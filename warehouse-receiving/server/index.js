require('dotenv').config();
const path = require('path');
const os = require('os');
const express = require('express');
const cors = require('cors');
const routes = require('./routes');
const { HttpError } = require('./utils/http');

const app = express();
app.use(cors());
app.use(express.json());

app.use('/uploads', express.static(path.join(__dirname, 'uploads'))); // anh hang hu hong
app.get('/api/health', (req, res) => res.json({ ok: true }));
app.use('/api/v1', routes);

// 404 cho route khong ton tai
app.use((req, res, next) => next(new HttpError(404, 'Không tìm thấy endpoint', 'NOT_FOUND')));

// Error middleware tap trung
// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  if (err instanceof HttpError) {
    return res.status(err.status).json({ error: { code: err.code, message: err.message, ...err.extra } });
  }
  if (err.type === 'entity.parse.failed') {
    return res.status(400).json({ error: { code: 'BAD_JSON', message: 'JSON không hợp lệ' } });
  }
  // Loi Postgres: 23505 = unique_violation (du phong neu co noi khac chen trung)
  if (err.code === '23505') {
    return res.status(409).json({ error: { code: 'DUPLICATE', message: 'Dữ liệu bị trùng (vi phạm ràng buộc unique)' } });
  }
  if (err.code === '22P02') { // invalid_text_representation (vd enum sai)
    return res.status(400).json({ error: { code: 'INVALID_VALUE', message: 'Giá trị không hợp lệ' } });
  }
  console.error(err);
  res.status(500).json({ error: { code: 'INTERNAL', message: 'Lỗi máy chủ' } });
});

const PORT = process.env.PORT || 3000;
if (require.main === module) {
  // Lang nghe tren moi giao dien mang de dien thoai trong cung Wi-Fi goi duoc
  app.listen(PORT, '0.0.0.0', () => {
    console.log(`API chay tai http://localhost:${PORT}`);
    for (const list of Object.values(os.networkInterfaces()))
      for (const n of list || []) if (n.family === 'IPv4' && !n.internal) console.log(`  Dien thoai dung dia chi: http://${n.address}:${PORT}`);
  });
}
module.exports = app;
