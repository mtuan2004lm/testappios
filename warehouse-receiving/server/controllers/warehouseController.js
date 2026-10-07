const db = require('../config/db');
const { asyncHandler } = require('../utils/http');

// GET /api/v1/warehouse/rules - danh sach quy tac regex dang bat (Web + iOS dung chung)
exports.listRules = asyncHandler(async (req, res) => {
  const includeInactive = req.query.include_inactive === 'true';
  const { rows } = await db.query(
    `SELECT id, customer_group, pattern_regex, business_type, requires_import_check, is_active, created_at
       FROM warehouse_rules
      ${includeInactive ? '' : 'WHERE is_active = TRUE'}
      ORDER BY id`
  );
  res.json({ data: rows });
});
