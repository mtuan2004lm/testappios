-- =====================================================================
-- Warehouse Receiving System - PostgreSQL schema
-- Chay nhieu lan van an toan (idempotent): enum/bang/seed chi tao neu chua co.
--   psql -d warehouse -f schema.sql      hoac      npm run db:init
-- =====================================================================

-- 1. Enum: loai hinh kinh doanh, trang thai phien, trang thai ngoai le ----
DO $$ BEGIN
  CREATE TYPE business_type_enum AS ENUM ('KINH_DOANH', 'KHONG_KINH_DOANH');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE session_status_enum AS ENUM ('OPEN', 'CLOSED');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE item_exception_enum AS ENUM ('NORMAL', 'UNKNOWN', 'DAMAGED', 'HOLDING', 'BLOCKED', 'DUPLICATE');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 2. Quy tac phan loai Ma Kho (dynamic rules) -----------------------------
CREATE TABLE IF NOT EXISTS warehouse_rules (
  id                    SERIAL PRIMARY KEY,
  customer_group        VARCHAR(50)  NOT NULL,   -- Giaonhan247, FADO 168, MICAFI, FADO.VN
  pattern_regex         VARCHAR(150) NOT NULL,   -- regex (cu phap JS/POSIX tuong thich) khop voi detected_text
  business_type         business_type_enum NOT NULL,
  requires_import_check BOOLEAN DEFAULT FALSE,   -- TRUE: hang kinh doanh can kiem tra dieu kien nhap khau
  is_active             BOOLEAN DEFAULT TRUE,
  created_at            TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Seed mac dinh (chi chen khi bang con trong)
INSERT INTO warehouse_rules (customer_group, pattern_regex, business_type, requires_import_check)
SELECT * FROM (VALUES
  ('Giaonhan247', '^(SGKYDUYEN_|HNKYDUYEN_|SGVO_|HNVO_)',                                   'KHONG_KINH_DOANH'::business_type_enum, FALSE),
  ('FADO 168',    '^(CHHEN_|SG HUE_DOFA168|SG FRAGILE_DOFA168)',                            'KHONG_KINH_DOANH'::business_type_enum, FALSE),
  ('MICAFI',      '(MCF$|MCF\s)',                                                           'KHONG_KINH_DOANH'::business_type_enum, FALSE),
  ('FADO.VN',     '^(FDVAT HUE|SGHUE DOFA|HNBANGTY DOFA|SG FRAGILE DOFA|HN FRAGILE DOFA)', 'KINH_DOANH'::business_type_enum,       TRUE)
) AS v(customer_group, pattern_regex, business_type, requires_import_check)
WHERE NOT EXISTS (SELECT 1 FROM warehouse_rules);

-- 3. Phien nhan hang (receiving sessions) ---------------------------------
CREATE TABLE IF NOT EXISTS receiving_sessions (
  id                      SERIAL PRIMARY KEY,
  carrier_name            VARCHAR(50)  NOT NULL,           -- DHL, Amazon Logistics, UPS, FedEx...
  driver_name             VARCHAR(100),
  license_plate           VARCHAR(50),
  gate_code               VARCHAR(20)  DEFAULT 'OR_1 - D2',
  opened_by               VARCHAR(50)  NOT NULL DEFAULT 'Nhan vien 01',
  status                  session_status_enum NOT NULL DEFAULT 'OPEN',
  total_expected_packages INT DEFAULT 0,
  scanned_count           INT DEFAULT 0,
  duplicate_count         INT DEFAULT 0,                   -- so lan quet trung ma (khong luu thanh dong rieng vi UNIQUE)
  arrival_time            TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  departure_time          TIMESTAMP WITH TIME ZONE,
  created_at              TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 4. Kien hang da quet (scanned items) ------------------------------------
CREATE TABLE IF NOT EXISTS scanned_items (
  id                      BIGSERIAL PRIMARY KEY,
  session_id              INT NOT NULL REFERENCES receiving_sessions(id) ON DELETE CASCADE,
  barcode                 VARCHAR(100) NOT NULL,
  detected_warehouse_code VARCHAR(100),
  matched_rule_id         INT REFERENCES warehouse_rules(id),
  customer_group          VARCHAR(50),
  business_type           business_type_enum,
  exception_status        item_exception_enum DEFAULT 'NORMAL',
  scanned_by              VARCHAR(50) NOT NULL DEFAULT 'Nhan vien 01',
  scanned_at              TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT unique_barcode_per_session UNIQUE (session_id, barcode)
);

-- Index phuc vu danh sach / loc
CREATE INDEX IF NOT EXISTS idx_sessions_status_arrival ON receiving_sessions (status, arrival_time DESC);
CREATE INDEX IF NOT EXISTS idx_sessions_carrier        ON receiving_sessions (carrier_name);
CREATE INDEX IF NOT EXISTS idx_items_session_scanned   ON scanned_items (session_id, scanned_at DESC);

-- 5. Danh sach ma tracking du kien (dung chung toan kho) ------------------
-- Quet ma co trong bang nay -> nhan binh thuong; khong co -> van nhan nhung danh dau UNKNOWN.
CREATE TABLE IF NOT EXISTS tracking_codes (
  id             BIGSERIAL PRIMARY KEY,
  barcode        VARCHAR(100) NOT NULL UNIQUE,
  warehouse_code VARCHAR(100),   -- ma kho in tren nhan (vd SGVO_123); dung de khop rule neu app khong gui detected_text
  note           VARCHAR(200),
  created_at     TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 6. Anh hang hu hong chup tu app iOS (gan vao kien vua quet) -------------
CREATE TABLE IF NOT EXISTS item_photos (
  id         BIGSERIAL PRIMARY KEY,
  item_id    BIGINT NOT NULL REFERENCES scanned_items(id) ON DELETE CASCADE,
  file_path  VARCHAR(200) NOT NULL,   -- duong dan URL, vd /uploads/item-12-1700000000.jpg
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_item_photos_item ON item_photos (item_id);
