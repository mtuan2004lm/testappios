// Đặt ngoại lệ "Không xác định" cho các kiện NO NAME đang là "Bình thường" (cả các phiên cũ).
//   npm run db:fix-noname
// Kiện NO NAME đã được đổi tay sang Hư hỏng / Đang giữ / Bị chặn thì giữ nguyên. Chạy lại nhiều lần vẫn an toàn.
const { pool } = require('../config/db');
(async () => {
  try {
    const r = await pool.query(
      "UPDATE scanned_items SET exception_status = 'UNKNOWN' WHERE is_no_name = TRUE AND exception_status = 'NORMAL' RETURNING id");
    console.log(`[ok] Đã đổi ${r.rowCount} kiện NO NAME sang "Không xác định".`);
  } catch (e) { console.error(e.message); process.exitCode = 1; } finally { await pool.end(); }
})();
