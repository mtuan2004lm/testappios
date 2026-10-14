// Tính lại Nhóm KH / Mã kho / Loại hình cho các kiện ĐÃ quét, theo quy tắc hiện tại trong bảng warehouse_rules.
//   npm run db:recompute
// - Kiện có mã kho đọc từ nhãn: khớp lại quy tắc -> cập nhật nhóm KH, loại hình, quy tắc.
// - Kiện mà "mã kho" chỉ là chính barcode (do gõ tay trên web, không khớp quy tắc): xóa mã kho cho khỏi lặp lại barcode.
// Lưu ý: loại hình đã đổi tay (KINH_DOANH <-> KHONG_KINH_DOANH) sẽ được tính lại theo quy tắc.
const { pool } = require('../config/db');
const { matchRule } = require('../utils/ruleMatcher');
// --clear-only: CHỈ xóa "mã kho" bị ghi nhầm là mã tracking, KHÔNG tính lại nhóm KH / loại hình (giữ nguyên các chỉnh sửa tay)
const CLEAR_ONLY = process.argv.includes('--clear-only');
const squash = (v) => String(v || '').replace(/[\x00-\x1F\x7F\s]+/g, '').toUpperCase();

(async () => {
  const client = await pool.connect();
  try {
    const rules = (await client.query('SELECT * FROM warehouse_rules WHERE is_active = TRUE ORDER BY id')).rows;
    const items = (await client.query('SELECT id, barcode, detected_warehouse_code AS text FROM scanned_items')).rows;
    let changed = 0, cleared = 0;
    await client.query('BEGIN');
    for (const it of items) {
      const rule = it.text ? matchRule(it.text, rules) : null;
      // Mã kho thực chất là tracking: trùng barcode (bỏ khoảng trắng / ký tự ẩn) hoặc chỉ gồm chữ số dài, và không khớp quy tắc nào
      const clearText = !!it.text && !rule && (squash(it.text) === squash(it.barcode) || /^\d{10,}$/.test(squash(it.text)));
      if (CLEAR_ONLY) {
        if (!clearText) continue;
        const r = await client.query('UPDATE scanned_items SET detected_warehouse_code = NULL WHERE id = $1', [it.id]);
        if (r.rowCount) { changed++; cleared++; }
        continue;
      }
      const { rowCount } = await client.query(
        `UPDATE scanned_items
            SET detected_warehouse_code = $2, matched_rule_id = $3, customer_group = $4, business_type = $5
          WHERE id = $1 AND (detected_warehouse_code IS DISTINCT FROM $2 OR matched_rule_id IS DISTINCT FROM $3
                          OR customer_group IS DISTINCT FROM $4 OR business_type IS DISTINCT FROM $5)`,
        [it.id, clearText ? null : it.text, rule ? rule.id : null, rule ? rule.customer_group : null, rule ? rule.business_type : null]);
      if (rowCount) { changed++; if (clearText) cleared++; }
    }
    await client.query('COMMIT');
    console.log(`Đã kiểm tra ${items.length} kiện: cập nhật ${changed} kiện (xóa mã kho trùng barcode: ${cleared}).`);
  } catch (e) {
    await client.query('ROLLBACK').catch(() => {});
    console.error('Lỗi:', e.message); process.exitCode = 1;
  } finally { client.release(); await pool.end(); }
})();
