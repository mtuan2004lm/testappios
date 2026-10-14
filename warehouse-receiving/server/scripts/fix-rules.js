// Sửa quy tắc mã kho mặc định cho khớp với nhãn thật (khoảng trắng tùy chọn).
//   npm run db:fix-rules
// - Quy tắc FADO.VN cũ: ^(FDVAT HUE|SGHUE DOFA|...)  -> không khớp "FD VAT HUE" (có khoảng trắng giữa FD và VAT).
// - Quy tắc mới chấp nhận có hoặc không có khoảng trắng.
// An toàn: chỉ sửa khi quy tắc vẫn đang là bản mặc định cũ; nếu bạn đã tự sửa tay thì giữ nguyên.
const { pool } = require('../config/db');

const FIXES = [
  {
    group: 'FADO.VN',
    oldPattern: '^(FDVAT HUE|SGHUE DOFA|HNBANGTY DOFA|SG FRAGILE DOFA|HN FRAGILE DOFA)',
    newPattern: '^(FD ?VAT ?HUE|SG ?HUE DOFA|HN ?BANGTY DOFA|SG ?FRAGILE DOFA|HN ?FRAGILE DOFA)',
  },
];

(async () => {
  try {
    for (const f of FIXES) {
      const r = await pool.query(
        'UPDATE warehouse_rules SET pattern_regex = $1 WHERE customer_group = $2 AND pattern_regex = $3 RETURNING id',
        [f.newPattern, f.group, f.oldPattern]
      );
      console.log(r.rowCount ? `[ok] ${f.group}: đã sửa quy tắc #${r.rows[0].id}` : `[bỏ qua] ${f.group}: quy tắc không phải bản mặc định cũ (đã sửa trước đó?)`);
    }
    const all = await pool.query('SELECT id, customer_group, pattern_regex FROM warehouse_rules ORDER BY id');
    console.table(all.rows);
    console.log('Gợi ý: chạy "npm run db:recompute" để tính lại các kiện cũ chưa nhận mã kho (lưu ý: tính lại cả loại hình), rồi bật lại app để tải quy tắc mới.');
  } catch (e) { console.error(e.message); process.exitCode = 1; } finally { await pool.end(); }
})();
