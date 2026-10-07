// Chay schema.sql bang Node (khong can cai psql): npm run db:init
const fs = require('fs');
const path = require('path');
const { pool } = require('../config/db');

(async () => {
  try {
    const sql = fs.readFileSync(path.join(__dirname, '..', 'schema.sql'), 'utf8');
    await pool.query(sql);
    console.log('Da khoi tao schema thanh cong.');
  } catch (e) {
    console.error('Khoi tao schema that bai:', e.message);
    process.exitCode = 1;
  } finally {
    await pool.end();
  }
})();
