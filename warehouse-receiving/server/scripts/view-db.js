// Xem nhanh dữ liệu trong database (dùng đúng kết nối trong .env, không cần psql).
//   npm run db:view                  -> đếm số dòng + 10 dòng mới nhất của từng bảng
//   npm run db:view -- scanned_items -> 50 dòng mới nhất của một bảng
const { pool } = require('../config/db');

const TABLES = ['receiving_sessions', 'scanned_items', 'tracking_codes', 'warehouse_rules', 'item_photos', 'products', 'flights', 'bin_locations', 'holds', 'tracking_formats', 'label_scans'];

async function show(table, limit) {
  const total = (await pool.query(`SELECT COUNT(*) FROM ${table}`)).rows[0].count;
  const { rows } = await pool.query(`SELECT * FROM ${table} ORDER BY id DESC LIMIT ${limit}`);
  console.log(`\n=== ${table} (${total} dòng) ===`);
  if (rows.length) console.table(rows); else console.log('(trống)');
}

(async () => {
  try {
    const arg = process.argv[2];
    if (arg) {
      if (!TABLES.includes(arg)) throw new Error(`Bảng không hợp lệ. Chọn một trong: ${TABLES.join(', ')}`);
      await show(arg, 50);
    } else {
      for (const t of TABLES) await show(t, 10);
    }
  } catch (e) {
    console.error('Lỗi:', e.message);
    process.exitCode = 1;
  } finally {
    await pool.end();
  }
})();
