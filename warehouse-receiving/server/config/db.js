// Ket noi PostgreSQL bang connection pool (thu vien 'pg')
require('dotenv').config();
const { Pool } = require('pg');

const pool = new Pool(
  process.env.DATABASE_URL
    ? { connectionString: process.env.DATABASE_URL }
    : {} // pg tu doc PGHOST, PGPORT, PGUSER, PGPASSWORD, PGDATABASE
);

pool.on('error', (err) => console.error('[pg] Loi pool bat ngo:', err));

module.exports = {
  query: (text, params) => pool.query(text, params),
  // Lay client rieng de chay transaction
  getClient: () => pool.connect(),
  pool,
};
