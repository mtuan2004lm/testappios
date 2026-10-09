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

-- 7. Danh sach mat hang (trang "Danh sach mat hang") ----------------------
CREATE TABLE IF NOT EXISTS products (
  id             BIGSERIAL PRIMARY KEY,
  name           VARCHAR(300) NOT NULL,            -- Ten hang
  image_path     VARCHAR(200),                     -- URL anh, vd /uploads/product-3-170000.jpg
  quantity       INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),   -- SL
  filter_status  VARCHAR(20) NOT NULL DEFAULT 'UNFILTERED' CHECK (filter_status IN ('UNFILTERED','FILTERED')), -- Chua dich loc / Dich loc
  tracking_code  VARCHAR(100) NOT NULL,            -- Tracking
  alt_code       VARCHAR(100),                     -- Ma khac
  order_code     VARCHAR(100),                     -- Ma don hang
  partner_name   VARCHAR(100),                     -- Doi tac (dong tren)
  partner_note   VARCHAR(200),                     -- Doi tac (dong duoi)
  created_at     TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_products_tracking ON products (tracking_code);
CREATE INDEX IF NOT EXISTS idx_products_created  ON products (created_at DESC);

-- 7b. Chuyen bay (trang "Quan ly chuyen bay") ------------------------------
CREATE TABLE IF NOT EXISTS flights (
  id             BIGSERIAL PRIMARY KEY,
  name           VARCHAR(200) NOT NULL,            -- Ten chuyen bay, vd HONGPHAT-8899-HAN
  mawb           VARCHAR(50),                      -- Van don chu (Master Air Waybill)
  airline_code   VARCHAR(30),                      -- vd CHINA_AIRLINES
  airline_name   VARCHAR(100),                     -- vd China Airlines
  origin         VARCHAR(10),                      -- San bay di, vd PDX
  destination    VARCHAR(10),                      -- San bay den, vd HAN
  transport_mode VARCHAR(20) NOT NULL DEFAULT 'INFORMAL' CHECK (transport_mode IN ('INFORMAL','FORMAL')), -- Tieu ngach / Chinh ngach
  status         VARCHAR(20) NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN','CLOSED','ARRIVED')),       -- Dang gom / Da dong / Da den VN
  etd            TIMESTAMP,                        -- Du kien khoi hanh
  eta            TIMESTAMP,                        -- Du kien den
  box_count      INTEGER NOT NULL DEFAULT 0 CHECK (box_count >= 0),   -- Thung
  hawb_count     INTEGER NOT NULL DEFAULT 0 CHECK (hawb_count >= 0),  -- HAWB
  note           VARCHAR(500),
  created_at     TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_flights_status  ON flights (status);
CREATE INDEX IF NOT EXISTS idx_flights_created ON flights (created_at DESC);

-- 7c. Vi tri ke (trang "Vi tri ke") ----------------------------------------
CREATE TABLE IF NOT EXISTS bin_locations (
  id          BIGSERIAL PRIMARY KEY,
  code        VARCHAR(100) NOT NULL UNIQUE,        -- Ma vi tri, ghep tu cac o da dien: Khu-Tieu khu-Loi-Gia-Tang-O
  alias       VARCHAR(100),                        -- Ten goi
  zone        VARCHAR(20),                         -- Khu
  subzone     VARCHAR(20),                         -- Tieu khu
  aisle       VARCHAR(20),                         -- Loi
  rack        VARCHAR(20),                         -- Gia
  level       VARCHAR(20),                         -- Tang
  cell        VARCHAR(20),                         -- O
  created_at  TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 7d. Hang dang giu (trang "Hang dang giu") --------------------------------
CREATE TABLE IF NOT EXISTS holds (
  id              BIGSERIAL PRIMARY KEY,
  tracking_code   VARCHAR(100) NOT NULL,           -- Ma kien
  hold_code       VARCHAR(150) NOT NULL,           -- Ma vu, vd HOLD-<time>-<rand>-SELLER_RETURN_REQUEST
  hold_type       VARCHAR(20) NOT NULL DEFAULT 'WAREHOUSE' CHECK (hold_type IN ('WAREHOUSE','CUSTOMER')), -- Kho giu / Khach yeu cau
  reason_code     VARCHAR(50),
  reason          VARCHAR(300),                    -- Ly do giu
  status          VARCHAR(20) NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','RESOLVED')),
  bin_location_id BIGINT REFERENCES bin_locations(id) ON DELETE SET NULL,
  opened_at       TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  resolved_at     TIMESTAMP WITH TIME ZONE
);
CREATE INDEX IF NOT EXISTS idx_holds_status ON holds (status, hold_type);
CREATE INDEX IF NOT EXISTS idx_holds_opened ON holds (opened_at DESC);

-- 7e. Dinh dang ma tracking theo hang van chuyen -------------------------
-- Tu ma vach quet duoc, suy ra cac "ma ung vien" (tracking that) de doi chieu voi Danh sach mat hang.
-- extract_mode: FULL = giu nguyen | LAST = lay N ky tu cuoi | DROP_FIRST = bo N ky tu dau | REGEX = lay nhom khop (param la regex)
CREATE TABLE IF NOT EXISTS tracking_formats (
  id            SERIAL PRIMARY KEY,
  carrier       VARCHAR(30)  NOT NULL,             -- USPS, UPS, FEDEX, DHL, AMAZON
  name          VARCHAR(100) NOT NULL UNIQUE,      -- Mo ta ngan
  detect_regex  VARCHAR(200) NOT NULL,             -- Ap len ma da chuan hoa (bo khoang trang, chu hoa)
  extract_mode  VARCHAR(20)  NOT NULL DEFAULT 'FULL' CHECK (extract_mode IN ('FULL','LAST','DROP_FIRST','REGEX')),
  extract_param VARCHAR(200),
  is_active     BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order    INT NOT NULL DEFAULT 100
);
INSERT INTO tracking_formats (carrier, name, detect_regex, extract_mode, extract_param, sort_order) VALUES
  ('USPS',   'USPS: 420 + ZIP5 + tracking',              '^420\d{5}\d{20,}$',                  'DROP_FIRST', '8',   10),
  ('USPS',   'USPS: 420 + ZIP9 + tracking',              '^420\d{9}\d{20,}$',                  'DROP_FIRST', '12',  11),
  ('USPS',   'USPS: 20–34 số bắt đầu bằng 9',            '^9\d{19,33}$',                        'FULL',       NULL,  12),
  ('USPS',   'USPS quốc tế: 2 chữ + 9 số + US',          '^[A-Z]{2}\d{9}US$',                   'FULL',       NULL,  13),
  ('UPS',    'UPS: 1Z + 16 ký tự (kể cả khi nằm trong chuỗi dài)', '1Z[0-9A-Z]{16}',            'REGEX',      '1Z[0-9A-Z]{16}', 20),
  ('FEDEX',  'FedEx Express: mã vạch 30–34 số, tracking = 12 số cuối', '^\d{30,34}$',           'LAST',       '12',  30),
  ('FEDEX',  'FedEx Ground: mã vạch 96 + 20 số, tracking = 15 số cuối', '^96\d{20}$',          'LAST',       '15',  31),
  ('FEDEX',  'FedEx SmartPost / Ground Economy: 92 + 20 số', '^92\d{20}$',                      'LAST',       '20',  32),
  ('FEDEX',  'FedEx: 12 hoặc 15 số in trên nhãn',        '^(\d{12}|\d{15})$',                  'FULL',       NULL,  33),
  ('DHL',    'DHL Express: 10 số',                       '^\d{10}$',                            'FULL',       NULL,  40),
  ('DHL',    'DHL eCommerce: JD / JJD / JVGL / GM + số', '^(JD|JJD|JVGL|GM)\d{16,20}$',         'FULL',       NULL,  41),
  ('AMAZON', 'Amazon Logistics: TBA / TBC / TBM + 12 số (kể cả khi nằm trong chuỗi dài)', 'TB[ACM]\d{12}', 'REGEX', 'TB[ACM]\d{12}', 50)
ON CONFLICT (name) DO NOTHING;

-- Moi don hang toi da 3 ma tracking: tracking_code + alt_code + alt_code2
ALTER TABLE products ADD COLUMN IF NOT EXISTS alt_code2 VARCHAR(100);

-- Ma da chuan hoa (bo khoang trang, chu hoa) de doi chieu nhanh bang chi muc
ALTER TABLE products ADD COLUMN IF NOT EXISTS tracking_norm TEXT GENERATED ALWAYS AS (upper(regexp_replace(tracking_code, '\s', '', 'g'))) STORED;
ALTER TABLE products ADD COLUMN IF NOT EXISTS alt_norm      TEXT GENERATED ALWAYS AS (upper(regexp_replace(coalesce(alt_code, ''), '\s', '', 'g'))) STORED;
ALTER TABLE products ADD COLUMN IF NOT EXISTS alt2_norm     TEXT GENERATED ALWAYS AS (upper(regexp_replace(coalesce(alt_code2, ''), '\s', '', 'g'))) STORED;
CREATE INDEX IF NOT EXISTS idx_products_alt2_norm     ON products (alt2_norm) WHERE alt2_norm <> '';
CREATE INDEX IF NOT EXISTS idx_products_tracking_norm ON products (tracking_norm);
CREATE INDEX IF NOT EXISTS idx_products_alt_norm      ON products (alt_norm) WHERE alt_norm <> '';

-- Kien da quet: hang van chuyen nhan dien duoc + ma tracking (trong danh sach) da khop, dung de chan trung giua cac dang ma
ALTER TABLE scanned_items ADD COLUMN IF NOT EXISTS detected_carrier VARCHAR(30);
ALTER TABLE scanned_items ADD COLUMN IF NOT EXISTS matched_tracking VARCHAR(100);
ALTER TABLE scanned_items ADD COLUMN IF NOT EXISTS product_id BIGINT;   -- mat hang trong Danh sach mat hang da khop
CREATE INDEX IF NOT EXISTS idx_items_matched ON scanned_items (session_id, matched_tracking);

-- 8. Dong bo bo dem id (sequence) voi du lieu hien co ----------------------
-- Can khi du lieu duoc chep tu database khac (pg_dump --data-only): neu khong, INSERT moi se trung id (loi 409).
DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['receiving_sessions','scanned_items','tracking_codes','item_photos','products','flights','bin_locations','holds','tracking_formats','warehouse_rules'] LOOP
    EXECUTE format(
      'SELECT setval(pg_get_serial_sequence(%L, ''id''), GREATEST(COALESCE((SELECT MAX(id) FROM %I), 0), 1), (SELECT COUNT(*) > 0 FROM %I))',
      t, t, t);
  END LOOP;
END $$;

-- 9. Trang thai quet gan nhat cua phien (hien o khung READY tren web) ------
-- SUCCESS: app doc duoc barcode + ma kho va gui len. FAIL: khong doc duoc barcode nhung van doc duoc ma kho.
ALTER TABLE receiving_sessions ADD COLUMN IF NOT EXISTS last_scan_status    VARCHAR(10);
ALTER TABLE receiving_sessions ADD COLUMN IF NOT EXISTS last_scan_at        TIMESTAMP WITH TIME ZONE;
ALTER TABLE receiving_sessions ADD COLUMN IF NOT EXISTS last_scan_barcode   VARCHAR(100);
ALTER TABLE receiving_sessions ADD COLUMN IF NOT EXISTS last_scan_text      VARCHAR(100);   -- ma kho doc tren nhan
ALTER TABLE receiving_sessions ADD COLUMN IF NOT EXISTS last_scan_group     VARCHAR(100);   -- nhom kho
ALTER TABLE receiving_sessions ADD COLUMN IF NOT EXISTS last_scan_exception VARCHAR(20);    -- NORMAL | UNKNOWN (chi voi SUCCESS)
ALTER TABLE receiving_sessions ADD COLUMN IF NOT EXISTS fail_count          INT NOT NULL DEFAULT 0;  -- so nhan khong doc duoc barcode

-- CHE DO THU: bo rang buoc "moi ma chi quet 1 lan trong 1 phien" o muc CSDL; viec chan trung do code scanController quyet dinh
-- (bien moi truong BLOCK_DUPLICATES=true de bat lai). Cac phien khac nhau luon duoc quet lai cung mot ma.
ALTER TABLE scanned_items DROP CONSTRAINT IF EXISTS unique_barcode_per_session;
CREATE INDEX IF NOT EXISTS idx_items_session_barcode ON scanned_items (session_id, barcode);

-- 10. Quet tracking tuan tu tren mot tem (toi da 3 ma) + END CODE + anh label ------------------------
-- label_scans: moi tracking da quet. item_id IS NULL = tracking chua co thong tin, dang cho quet tiep / END CODE.
CREATE TABLE IF NOT EXISTS label_scans (
  id            BIGSERIAL PRIMARY KEY,
  session_id    INT NOT NULL REFERENCES receiving_sessions(id) ON DELETE CASCADE,
  item_id       BIGINT REFERENCES scanned_items(id) ON DELETE SET NULL,
  seq           SMALLINT NOT NULL,          -- 1..3: thu tu tracking tren tem
  barcode       VARCHAR(100) NOT NULL,
  product_id    BIGINT,                     -- co gia tri neu tracking nay co thong tin (khop Danh sach mat hang)
  carrier       VARCHAR(30),
  detected_text VARCHAR(100),
  created_at    TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_label_scans_pending ON label_scans (session_id) WHERE item_id IS NULL;
CREATE INDEX IF NOT EXISTS idx_label_scans_item ON label_scans (item_id);
ALTER TABLE scanned_items ADD COLUMN IF NOT EXISTS is_no_name BOOLEAN NOT NULL DEFAULT FALSE;  -- ca 3 tracking deu khong co thong tin: lay tracking dau lam goc
ALTER TABLE item_photos ADD COLUMN IF NOT EXISTS kind VARCHAR(10) NOT NULL DEFAULT 'DAMAGE';  -- DAMAGE | LABEL (anh label)
ALTER TABLE receiving_sessions ALTER COLUMN last_scan_status TYPE VARCHAR(20);                  -- them TRACK, NO_NAME
