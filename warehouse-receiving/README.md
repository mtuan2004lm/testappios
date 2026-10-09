# Warehouse Receiving System (TinaShipping - OR_1 Hub Oregon)

Node.js/Express + PostgreSQL + Vue 3 / Tailwind, kèm app iPhone (thư mục `../WarehouseScanner-iOS`) dùng camera làm máy quét.

```
server/   API Express (config/, controllers/, routes/, utils/, scripts/, schema.sql, index.js)
client/   Vue 3 SPA (src/views/: SessionList, SessionScan, ItemsList, TrackingCodes)
```

## Các màn hình web

| Tab | Đường dẫn | Chức năng |
|---|---|---|
| Nhận hàng | `/receiving/sessions` | Danh sách phiên tiếp nhận, tạo phiên (nhập tay số kiện) |
| (màn quét) | `/receiving/sessions/:id/scan` | Quét mã bằng máy quét, nhập tay hoặc **camera web**; sửa số kiện ngay trên trang; tự cập nhật mỗi 2 giây khi iPhone gửi mã về |
| (menu Nhận hàng ▾) Hàng đang giữ | `/receiving/detained` | Kiện chưa được bay: tab *Kho giữ / Hold*, *Khách yêu cầu / Block*, *Đã xử lý*; lọc, gán vị trí, đánh dấu đã xử lý (xem mục bên dưới) |
| (menu Nhận hàng ▾) Định dạng mã tracking | `/receiving/tracking-formats` | Bảng định dạng mã theo hãng + ô **Thử mã vạch** (xem mục bên dưới) |
| (menu Nhận hàng ▾) Vị trí kệ | `/receiving/bin-locations` | Quản lý vị trí kệ trong kho; thêm một hoặc nhiều vị trí (xem mục bên dưới) |
| Danh sách mặt hàng | `/items` | Danh sách đơn hàng/mặt hàng (xem mục bên dưới). **Quyết định mã quét có "xác định" hay không** |
| Chuyến bay ▾ → Quản lý chuyến bay | `/flights` | Quản lý chuyến bay gom hàng (xem mục bên dưới) |
| Chuyến bay ▾ → Chờ vào box | `/flights/waiting` | Trang tạm, chưa có chức năng |
| Báo cáo tracking | `/reports` | Quản lý danh sách mã tracking cũ: nhập hàng loạt, tạo mã thử, in/xem mã vạch |

### Danh sách mặt hàng (`/items`)
- Bảng: STT, Ảnh, Tên hàng (kèm nhãn *Chưa dịch lọc / Dịch lọc* và SL), Tracking (kèm *Mã khác*), Mã đơn hàng, Đối tác, nút con mắt.
- Tìm theo Mã tracking / Mã đơn hàng / Tên hàng / Đối tác; 3 tab *Tất cả / Chưa dịch lọc / Dịch lọc*; phân trang 20/50/100.
- Nút **Thêm mặt hàng**: form nhập Tên hàng*, SL, Trạng thái, Tracking*, Mã khác, Mã đơn hàng, Đối tác, Ghi chú đối tác, Ảnh (\* bắt buộc). Bấm **con mắt** để xem / sửa / xóa.
- Không có dữ liệu mẫu: danh sách trống cho tới khi bạn thêm.

## Quy tắc quét (quan trọng)

- Mã quét **chỉ được coi là bình thường (`NORMAL`)** khi trùng cột **Tracking** hoặc **Mã khác** của một mặt hàng trong *Danh sách mặt hàng* (không phân biệt hoa/thường).
- Mã không có trong danh sách **vẫn được nhận vào phiên** nhưng ghi `exception_status = UNKNOWN` ("Không xác định"). Nhóm kho vẫn được nhận diện từ mã kho trên nhãn.
- Trùng mã trong cùng phiên → **409 DUPLICATE_BARCODE**, tăng bộ đếm trùng.
- Nhóm kho/khách hàng: duyệt rule regex đang bật theo `id` tăng dần, rule đầu tiên khớp (không phân biệt hoa/thường) thắng. Nếu app gửi `detected_text` (mã kho đọc từ nhãn) thì dùng nó; nếu không thì dùng mã kho đã lưu trong bảng `tracking_codes`, hoặc chính barcode.
- Bảng `tracking_codes` (trang Báo cáo tracking) chỉ còn dùng để gợi ý mã kho, **không còn quyết định** mã xác định hay không.

## Chạy thử

1. Tạo database và cấu hình:
   ```bash
   createdb warehouse        # Postgres.app: /Applications/Postgres.app/Contents/Versions/latest/bin/createdb warehouse
   cd server
   cp .env.example .env      # sửa DATABASE_URL, vd: postgres://minhtuan@localhost:5432/warehouse
   npm install
   npm run db:init           # chạy schema.sql (chạy lại nhiều lần vẫn an toàn)
   npm run dev               # API: http://localhost:3000 (cũng in địa chỉ LAN cho iPhone)
   ```
2. Frontend (terminal khác):
   ```bash
   cd client
   npm install
   npm run dev               # http://localhost:5173 (tự proxy /api và /uploads -> :3000)
   ```
3. Cần **2 terminal chạy song song** (server cổng 3000, client cổng 5173). Báo `EADDRINUSE` = còn server cũ giữ cổng: `kill -9 $(lsof -ti :3000)` rồi chạy lại.
4. Sau mỗi lần cập nhật code có đổi bảng: chạy lại `npm run db:init`, rồi khởi động lại server.

### Xem database
```bash
cd server
npm run db:view                    # tóm tắt các bảng
npm run db:view -- scanned_items   # một bảng
```
Hoặc dùng Postgres.app: bấm đúp database `warehouse` rồi gõ `\dt`, `SELECT * FROM products;`.
Muốn gõ `psql` trực tiếp: thêm `export PATH="/Applications/Postgres.app/Contents/Versions/latest/bin:$PATH"` vào `~/.zshrc`.
### Quản lý chuyến bay (`/flights`)
- 3 tab *Tất cả / Đang gom / Đã đóng chuyến* (có số đếm; "Đã đóng chuyến" gồm cả *Đã đóng* và *Đã đến VN*).
- Lọc: tên chuyến hoặc MAWB (Enter để tìm), hãng bay, hình thức (*Tiểu ngạch / Chính ngạch*), loại ngày (Ngày tạo / ETD / ETA) + khoảng ngày; **Bộ lọc nâng cao**: sân bay đi, sân bay đến, trạng thái; nút *Xoá lọc*.
- Bảng: Chuyến bay/MAWB/hãng, Tuyến + hình thức, Trạng thái, ETD/ETA, Thùng/HAWB, Ngày tạo, Thao tác. Nút **+** mở rộng dòng; **con mắt** xem/sửa/xóa (chuyến đã có thùng không xóa được); **✕** đóng chuyến (có xác nhận).
- Nút **Tạo chuyến bay mới**: tên*, MAWB, hãng, sân bay đi/đến, hình thức, ETD, ETA, số thùng, số HAWB, ghi chú. Không có dữ liệu mẫu.
- Danh sách hãng bay đang cố định trong `client/src/views/FlightsManagement.vue` (mảng `AIRLINES`).

### Hàng đang giữ (`/receiving/detained`)
- Tab *Kho giữ / Hold* (loại `WAREHOUSE`), *Khách yêu cầu / Block* (loại `CUSTOMER`), *Đã xử lý*; số đếm theo bộ lọc.
- Lọc: mã kiện / mã vụ, ô *Chưa có vị trí*, chọn *Vị trí*, nhanh theo ngày (Tất cả, Hôm nay, Hôm qua, 7 ngày, Tháng này, Tháng trước, Tuỳ chọn).
- Bảng: Mã tracking (sao chép được), Mã vụ (tự sinh `HOLD-<thời gian>-<mã ngẫu nhiên>-<LÝ DO>`), Lý do giữ, Vị trí, Mở lúc, nút **Chi tiết** (gán vị trí, *Đánh dấu đã xử lý* / *Mở lại*, xóa).
- Tích chọn nhiều dòng → thanh thao tác hàng loạt: *Gán vị trí* và *Đánh dấu đã xử lý*.
- Nút **Thêm hàng giữ** để nhập tay (chưa tự tạo từ lúc quét); không có dữ liệu mẫu.

### Vị trí kệ (`/receiving/bin-locations`)
- Mỗi vị trí gồm 6 ô: **Khu, Tiểu khu, Lối, Giá, Tầng, Ô** + *Tên gọi*. Cần điền ít nhất một ô; **mã vị trí tự ghép** từ các ô đã điền, ngăn bằng dấu `-` (Khu A + Giá 01 + Tầng 1 → `A-01-1`). Mã trùng bị từ chối (409).
- Tab **Thêm vị trí** (một vị trí) và **Thêm nhiều vị trí**: mỗi ô nhận khoảng hoặc danh sách (`01-05`, `A-C`, `1,3,5`), hệ thống tạo mọi tổ hợp (tối đa 1000, mã đã có thì bỏ qua) và xem trước số lượng.
- Danh sách có tìm theo mã/tên gọi, sửa (bút chì), xóa (thùng rác). Xóa vị trí thì hàng đang giữ ở đó thành "chưa có vị trí".

### Định dạng mã tracking (`/receiving/tracking-formats`)
- Mỗi hãng in mã vạch khác nhau (FedEx 34 số, USPS có tiền tố `420`+ZIP, UPS `1Z…`, Amazon `TBA…`). Khi quét, server **chuẩn hóa** mã (bỏ khoảng trắng/ký tự ẩn, chữ hoa), rồi dựa vào bảng `tracking_formats` rút ra các **mã ứng viên** (vd FedEx 34 số → 12 số cuối) và so khớp chính xác với cột `tracking_norm` / `alt_norm` của Danh sách mặt hàng.
- Thứ tự thử: mã gốc → mã rút theo định dạng → (dự phòng) mã trong danh sách từ 10 ký tự nằm trong mã vạch. Kết quả khớp có `match_method` = `EXACT` / `DERIVED` / `CONTAINS` và `carrier` (hãng của **mã đã khớp**). Hãng và mã đã khớp được lưu vào kiện (`detected_carrier`, `matched_tracking`, `product_id`); cùng một kiện quét bằng mã khác → báo **MÃ TRÙNG**, không tính hai kiện.
- Định dạng mẫu có sẵn: USPS (420+ZIP5/ZIP9, 20–34 số bắt đầu bằng 9, quốc tế), UPS (`1Z`+16), FedEx (Express 30–34 số → 12 số cuối; Ground `96`+20 → 15 số cuối; SmartPost `92`+20; 12/15 số in trên nhãn), DHL (10 số; JD/JJD/JVGL/GM), Amazon (TBA/TBC/TBM+12). **Các định dạng này dựa trên quy ước thông dụng, cần kiểm lại với nhãn thật của từng hãng** — dùng ô *Thử mã vạch* để dán mã quét được và xem hệ thống rút ra mã nào, khớp mặt hàng nào; thiếu thì bấm *Thêm định dạng* (hãng, regex nhận biết, cách rút: giữ nguyên / lấy N ký tự cuối / bỏ N ký tự đầu / lấy phần khớp regex).
- **Phiên không giới hạn hãng**: phiên của hãng nào cũng quét được mã của mọi hãng. Một tem có thể có tối đa **3 mã tracking**: chỉ cần **1 trong các mã** có trong Danh sách mặt hàng là nhận. App iPhone gửi mã chính + các mã vạch khác trong cùng khung hình (`alt_barcodes`, tối đa 5); server thử lần lượt, mã nào khớp trước thì dùng và hiển thị **hãng của mã đó**. Không mã nào có trong danh sách → **FAIL** (`TRACKING_NOT_FOUND`). Mỗi mặt hàng có tối đa **3 mã tracking**: `tracking_code` + `alt_code` + `alt_code2` (form Danh sách mặt hàng có ô *Mã khác (1)* và *Mã khác (2)*); quét mã nào trong 3 mã cũng nhận, bảng kiện của phiên hiện dòng "Mã khác".
- Danh sách hãng khi tạo phiên: Amazon Logistics, Amazon Package, Amazon Pallet, DHL, FEDEX EXPRESS, FEDEX GROUND, FedEx, Other, UPS, USPS.
- Cột *Mã* trong lịch sử quét hiện thêm nhãn hãng nhận diện được.

Nếu không có `.env`, server dùng mặc định của `pg` (user máy, database trùng tên user) → nhớ tạo `.env` trỏ đúng `warehouse`.

## Bảng dữ liệu (`server/schema.sql`)

| Bảng | Nội dung |
|---|---|
| `warehouse_rules` | Quy tắc regex mã kho → nhóm khách hàng (Giaonhan247, FADO 168, MICAFI, FADO.VN) |
| `receiving_sessions` | Phiên tiếp nhận (số kiện dự kiến, đã quét, đếm trùng) |
| `scanned_items` | Kiện đã quét (UNIQUE phiên + barcode), nhóm kho, trạng thái ngoại lệ |
| `tracking_codes` | Danh sách mã tracking cũ + mã kho (dùng chung toàn kho) |
| `item_photos` | Ảnh hàng hỏng chụp từ app iOS |
| `flights` | **Chuyến bay** (tên, MAWB, hãng, tuyến, hình thức Tiểu/Chính ngạch, trạng thái OPEN/CLOSED/ARRIVED, ETD/ETA, thùng, HAWB) |
| `bin_locations` | **Vị trí kệ** (mã ghép từ Khu-Tiểu khu-Lối-Giá-Tầng-Ô, tên gọi) |
| `tracking_formats` | **Định dạng mã tracking theo hãng** (hãng, regex nhận biết, cách rút mã, bật/tắt, thứ tự) |
| `holds` | **Hàng đang giữ** (tracking, mã vụ, loại WAREHOUSE/CUSTOMER, lý do, trạng thái ACTIVE/RESOLVED, vị trí) |
| `products` | **Danh sách mặt hàng** (tên, ảnh, SL, trạng thái dịch lọc, tracking, mã khác, mã đơn hàng, đối tác) |

## API (tất cả endpoint đang dùng)

Địa chỉ gốc: `http://localhost:3000`. Mọi endpoint nghiệp vụ nằm dưới `/api/v1`. Web gọi qua proxy Vite (`/api` → `:3000`); app iPhone gọi thẳng địa chỉ server. Body là JSON (`Content-Type: application/json`) trừ các endpoint tải ảnh.

- **Thành công:** `{ "data": ... }` (danh sách có thêm `pagination` {page, limit, total, total_pages}, một số có `counts`).
- **Lỗi:** `{ "error": { "code": "...", "message": "..." } }` kèm mã HTTP (400 dữ liệu sai, 404 không thấy, 409 trùng, 422 mã không có trong danh sách, 500 lỗi máy chủ).
- Cột **Dùng bởi**: Web / iOS.

### Hệ thống

| Method | Đường dẫn | Mô tả | Dùng bởi |
|---|---|---|---|
| GET | `/api/health` | Kiểm tra server còn sống `{ok:true}` | iOS (nút kiểm tra kết nối) |
| GET | `/uploads/<file>` | Phục vụ ảnh tĩnh (ảnh mặt hàng, ảnh hàng hỏng) | Web |

### Quy tắc kho

| Method | Đường dẫn | Mô tả | Dùng bởi |
|---|---|---|---|
| GET | `/api/v1/warehouse/rules` | Quy tắc regex mã kho → nhóm KH / loại hình đang bật | Web, iOS |

### Phiên nhận hàng và quét

| Method | Đường dẫn | Mô tả | Dùng bởi |
|---|---|---|---|
| GET | `/api/v1/receiving/sessions?page&limit&status&carrier&date` | Danh sách phiên, phân trang + lọc | Web, iOS (`status=OPEN`) |
| POST | `/api/v1/receiving/sessions` | Tạo phiên (`carrier_name` bắt buộc, `total_expected_packages` nhập tay) | Web |
| GET | `/api/v1/receiving/sessions/:id` | Phiên + kiện đã quét + đếm ngoại lệ + kết quả quét gần nhất (`last_scan_*`); web hỏi lại mỗi 2 giây | Web |
| PATCH | `/api/v1/receiving/sessions/:id` | Sửa số kiện dự kiến `{total_expected_packages}` | Web |
| POST | `/api/v1/receiving/sessions/:id/scan` | `{barcode, detected_text, alt_barcodes?}`: tra Danh sách mặt hàng (kể cả mã USPS `420`+ZIP; thử `barcode` rồi các `alt_barcodes`), khớp regex mã kho, lưu kiện, trả `carrier` + `match_method`. Không có trong danh sách → **422 `TRACKING_NOT_FOUND`** (FAIL). Trùng kiện trong phiên → **409 `DUPLICATE_BARCODE`** (MÃ TRÙNG) | Web, iOS |
| POST | `/api/v1/receiving/sessions/:id/scan-fail` | `{detected_text}`: app đọc được mã kho nhưng không đọc được mã vạch; chỉ ghi khi mã kho khớp quy tắc (nếu không → 422); tăng bộ đếm FAIL | iOS |
| POST | `/api/v1/receiving/sessions/:id/classify` | `{barcode, detected_text}`: gán nhóm KH cho kiện đã quét (404 `ITEM_NOT_SCANNED` nếu chưa quét). Còn trong code, app hiện tại không gọi | (dự phòng) |
| PATCH | `/api/v1/receiving/sessions/:id/finalize` | "Chốt kiện": đặt tổng kiện = số đã quét | Web |
| PATCH | `/api/v1/receiving/sessions/:id/close` | Kết thúc phiên | Web |
| PATCH | `/api/v1/scanned-items/:id/toggle-business-type` | Đổi KINH_DOANH ⇄ KHONG_KINH_DOANH | Web |
| PATCH | `/api/v1/scanned-items/:id/exception` | `{exception_status}` đánh dấu hư hỏng / giữ hàng / chặn / không xác định / bình thường | Web |
| POST | `/api/v1/scanned-items/:id/damage-photo` | Ảnh thô `image/*` (≤10MB), gắn vào kiện, đánh dấu DAMAGED | iOS |

### Danh sách mặt hàng

| Method | Đường dẫn | Mô tả | Dùng bởi |
|---|---|---|---|
| GET | `/api/v1/products?filter&field&search&page&limit` | `filter`: UNFILTERED/FILTERED; `field`: tracking/order/name/partner | Web |
| POST | `/api/v1/products` | Thêm mặt hàng (`name`, `tracking_code` bắt buộc) | Web |
| PUT | `/api/v1/products/:id` | Sửa mặt hàng (gửi đủ các trường) | Web |
| DELETE | `/api/v1/products/:id` | Xóa mặt hàng (và ảnh) | Web |
| POST | `/api/v1/products/:id/image` | Tải ảnh thô `image/*` (≤10MB) | Web |
| DELETE | `/api/v1/products/:id/image` | Bỏ ảnh | Web |

### Báo cáo tracking (mã tracking cũ)

| Method | Đường dẫn | Mô tả | Dùng bởi |
|---|---|---|---|
| GET | `/api/v1/tracking-codes` | Danh sách mã tracking | Web |
| POST | `/api/v1/tracking-codes/bulk` | Nhập hàng loạt `{items}` | Web |
| POST | `/api/v1/tracking-codes/generate` | Tạo mã thử `{count}` | Web |
| DELETE | `/api/v1/tracking-codes/:id` | Xóa một mã | Web |

### Chuyến bay

| Method | Đường dẫn | Mô tả | Dùng bởi |
|---|---|---|---|
| GET | `/api/v1/flights?tab&search&airline&mode&date_field&from&to&origin&destination&status&page&limit` | `tab`: ALL/OPEN/CLOSED; trả thêm `counts` {all, open, closed} | Web |
| POST | `/api/v1/flights` | Tạo chuyến (`name` bắt buộc) | Web |
| PUT | `/api/v1/flights/:id` | Sửa chuyến | Web |
| PATCH | `/api/v1/flights/:id/status` | `{status}`: OPEN / CLOSED / ARRIVED | Web |
| DELETE | `/api/v1/flights/:id` | Xóa chuyến (409 `FLIGHT_HAS_BOXES` nếu đã có thùng) | Web |

### Hàng đang giữ

| Method | Đường dẫn | Mô tả | Dùng bởi |
|---|---|---|---|
| GET | `/api/v1/holds?tab&search&no_location&location&from&to&page&limit` | `tab`: HOLD/BLOCK/DONE; trả thêm `counts` {hold, block, done} | Web |
| POST | `/api/v1/holds` | `{tracking_code, hold_type, reason_code, reason, bin_location_id}`; mã vụ tự sinh | Web |
| PATCH | `/api/v1/holds/:id` | Sửa một phần: `bin_location_id`, `status` (ACTIVE/RESOLVED), `reason` | Web |
| PATCH | `/api/v1/holds/bulk` | `{ids, action: "assign" \| "resolve", bin_location_id}` | Web |
| DELETE | `/api/v1/holds/:id` | Xóa bản ghi giữ hàng | Web |

### Định dạng mã tracking

| Method | Đường dẫn | Mô tả | Dùng bởi |
|---|---|---|---|
| GET | `/api/v1/tracking-formats` | Danh sách định dạng mã theo hãng | Web |
| POST | `/api/v1/tracking-formats` | Thêm định dạng `{carrier, name, detect_regex, extract_mode, extract_param, is_active, sort_order}` (400 nếu regex sai) | Web |
| POST | `/api/v1/tracking-formats/test` | `{barcode, carrier_name?}` thử đối chiếu, không ghi gì: trả mã chuẩn hóa, hãng, cách khớp, các mã ứng viên, mặt hàng khớp | Web |
| PUT | `/api/v1/tracking-formats/:id` | Sửa định dạng (cũng dùng để bật/tắt) | Web |
| DELETE | `/api/v1/tracking-formats/:id` | Xóa định dạng | Web |

### Vị trí kệ

| Method | Đường dẫn | Mô tả | Dùng bởi |
|---|---|---|---|
| GET | `/api/v1/bin-locations?search` | Danh sách vị trí + `total` | Web |
| POST | `/api/v1/bin-locations` | Thêm một vị trí `{zone, subzone, aisle, rack, level, cell, alias}`; 409 `LOCATION_EXISTS` nếu trùng mã | Web |
| POST | `/api/v1/bin-locations/bulk` | `{items: [...]}` tối đa 1000, bỏ qua mã đã có, trả `{created, skipped}` | Web |
| PUT | `/api/v1/bin-locations/:id` | Sửa vị trí (mã tự ghép lại) | Web |
| DELETE | `/api/v1/bin-locations/:id` | Xóa vị trí (hàng giữ ở đó thành "chưa có vị trí") | Web |

Ảnh được lưu trong `server/uploads/` và phục vụ qua `/uploads/...`. Endpoint không tồn tại trả 404 `NOT_FOUND`.

## App iPhone

Xem `../WarehouseScanner-iOS/README.md`. Tóm tắt: iPhone chỉ làm máy quét; phiên tạo trên web; mỗi nhãn quét một lần lấy cả mã vạch + mã kho (OCR) và tự gửi về `/scan`; app hiển thị nhãn thuộc kho nào, và thẻ cam **KHÔNG XÁC ĐỊNH** nếu mã không có trong Danh sách mặt hàng. Nếu iPhone không nối được server: cùng Wi-Fi, cho phép *Local Network*, hoặc dùng `cloudflared tunnel --url http://localhost:3000` rồi nhập địa chỉ https vào ⚙️ trong app.

## Lịch sử cập nhật

- Khởi tạo hệ thống nhận hàng: phiên, quét, rule regex, ngoại lệ, trùng mã.
- Thêm danh sách mã tracking toàn kho; nhập tay số kiện khi mở phiên và sửa ngay trên màn quét; quét bằng camera web (ZXing).
- App iOS (Swift/SwiftUI): camera liên tục, OCR mã kho, một lần quét gửi cả mã vạch + mã kho, tự duyệt, bỏ qua nhãn lỗi, hàng đợi gửi lại, chụp ảnh báo hỏng; app không tạo phiên và không phân loại kinh doanh.
- Công cụ xem database (`npm run db:view`); tách database riêng `warehouse`.
- Trang **Danh sách mặt hàng** (bảng `products`, form thêm/sửa/xóa, ảnh, tìm kiếm, tab lọc); trang quản lý tracking cũ chuyển sang tab *Báo cáo tracking*.
- Quy tắc mới: mã chỉ "xác định" khi có trong Danh sách mặt hàng, còn lại là **Không xác định** (cả web và app).
- Khung **READY** trên màn quét web nay hiện kết quả từ app iPhone trong ~8 giây: **SUCCESS** (đọc được mã vạch + mã kho) hoặc **FAIL** (không đọc được mã vạch nhưng vẫn đọc được mã kho; không tạo kiện). Thêm API `POST /receiving/sessions/:id/scan-fail {detected_text}` (chỉ ghi khi mã kho khớp quy tắc), bộ đếm "Không đọc được mã vạch" ở mục Ngoại lệ, các cột `last_scan_*` và `fail_count` trong `receiving_sessions`. Sau khi cập nhật chạy `npm run db:init`.
- Sửa lỗi 409 khi tạo phiên sau khi chép dữ liệu giữa các database: `schema.sql` tự đồng bộ lại bộ đếm id.
- App iOS tự dùng địa chỉ server mặc định (`AppStore.defaultServerURL`, tên máy `.local`) khi mới cài.
- **Đổi quy tắc quét (thay cho "Không xác định")**: mã **không có trong Danh sách mặt hàng bị từ chối** (HTTP 422 `TRACKING_NOT_FOUND`) trên cả web lẫn app iPhone: không tạo kiện, không tính vào số đã quét, khung READY hiện **FAIL** + "Mã không có trong danh sách mặt hàng", tăng bộ đếm *Quét thất bại (FAIL)*. Mã có trong danh sách → nhận bình thường (SUCCESS).
- Tốc độ quét app iOS: cửa sổ gom mã vạch + mã kho giảm từ 3,5 giây xuống **2 giây**; OCR ~4 khung/giây (trước ~2); timeout gửi mã 3 giây.
- Tăng tốc camera app iOS: đọc chữ chế độ nhanh (`.fast`, ~8 khung/giây), cứ 4 lần có 1 lần đọc kỹ (`.accurate`); giới hạn tầm lấy nét gần (`autoFocusRangeRestriction = .near`) để nét nhanh; bật tăng sáng khi thiếu sáng; giảm thời gian chờ giữa hai lần quét cùng mã xuống 1,5 giây.
- Khớp mã USPS: mã vạch dạng "420" + ZIP (5 hoặc 9 số) + tracking thật (vd `420 97220 9334610990150197272857`) cũng khớp với mặt hàng có Tracking/Mã khác là phần sau tiền tố 420+ZIP.
- Sửa lỗi quét mã USPS dạng GS1-128: mã vạch chứa ký tự điều khiển ẩn `GS` (0x1D) giữa ZIP và tracking (`42097220<GS>9334…`). Server loại bỏ mọi ký tự điều khiển khỏi barcode trước khi so khớp và lưu.
- Sửa lỗi báo FAIL oan khi quét lại nhãn đã quét: app iPhone nay phân biệt "nhãn vẫn nằm trong khung" (im lặng) với "rời khung rồi quét lại" (báo **MÃ TRÙNG**, không FAIL). Server ghi `last_scan_status = DUPLICATE` nên web cũng hiện MÃ TRÙNG ở khung READY và tăng bộ đếm Mã trùng. Chữ mã kho của nhãn đã gửi không còn bị coi là nhãn mới thiếu mã vạch.
- **Tách riêng 3 cột Nhóm KH / Mã kho / Loại hình**: bảng lịch sử quét trên web có thêm cột *Mã kho* (chữ đọc trên nhãn, `detected_warehouse_code`); khung SUCCESS trên web và thẻ SUCCESS trên app iPhone hiện đủ 3 dòng riêng. Mã vạch gõ tay trên web không còn bị ghi lặp vào cột Mã kho. Thêm `npm run db:recompute` để tính lại Nhóm KH / Loại hình / Mã kho cho các kiện đã quét theo quy tắc hiện tại (an toàn khi chạy lại; loại hình đã đổi tay sẽ được tính lại).
- **Menu thả xuống** trên thanh điều hướng: *Nhận hàng ▾* (Phiên nhận hàng, Hàng đang giữ, Vị trí kệ) và *Chuyến bay ▾* (Quản lý chuyến bay, Chờ vào box); bấm ra ngoài để đóng.
- Trang **Quản lý chuyến bay** (`/flights`, bảng `flights`, API `/flights`): tab, bộ lọc + lọc nâng cao, bảng mở rộng được, tạo/xem/sửa/xóa, đóng chuyến. Trang *Chờ vào box* là trang tạm.
- Trang **Hàng đang giữ** (`/receiving/detained`, bảng `holds`, API `/holds`): 3 tab, lọc theo vị trí/ngày, thao tác hàng loạt, chi tiết, thêm tay.
- Trang **Vị trí kệ** (`/receiving/bin-locations`, bảng `bin_locations`, API `/bin-locations`): mã vị trí tự ghép từ 6 ô, thêm một hoặc nhiều vị trí theo khoảng, tìm/sửa/xóa.
- Cách cập nhật cho 3 trang mới: chạy `npm run db:init` trong `server` (tạo 3 bảng mới, an toàn khi chạy lại), khởi động lại server, tải lại web. `npm run db:view` xem được thêm bảng `flights`, `bin_locations`, `holds`.
- Tài liệu ngoài dự án: file **báo cáo PDF** "Hệ thống nhận hàng tại kho" (5 trang) để trình bày với cấp trên; tổng hợp vấn đề/giải pháp, kiến trúc, màn hình web, quy tắc quét SUCCESS/FAIL/MÃ TRÙNG, bảng mã kho → nhóm KH → loại hình, hiện trạng và đề xuất.
- Thanh điều hướng chỉ còn một kho **OR_1 - Hub Oregon** (bỏ danh sách CA_1, TX_1). README có mục *API (tất cả endpoint đang dùng)* liệt kê đầy đủ endpoint, kể cả `/api/health`, `/uploads` và `scan-fail`, kèm bên dùng (Web / iOS).
- **Khớp mã vạch FedEx dài**: nhãn FedEx có mã vạch dài (vd 34 số) chứa mã tracking in trên nhãn (vd `3004 7009 2728` = 12 số cuối). Server nay coi là khớp nếu mã trong Danh sách mặt hàng (từ 10 ký tự trở lên, bỏ khoảng trắng) nằm trong mã vạch quét được. Quy tắc mã kho coi dấu `_` và khoảng trắng là như nhau (nhãn in `SG HUE DOFA168`, quy tắc viết `SG HUE_DOFA168`). Cần khởi động lại server.
- **Quét theo định dạng từng hãng vận chuyển**: thêm bảng `tracking_formats` (seed USPS, UPS, FedEx, DHL, Amazon), cột chuẩn hóa `products.tracking_norm` / `alt_norm` có chỉ mục, cột `scanned_items.detected_carrier` / `matched_tracking`, trang *Định dạng mã tracking* (có ô thử mã), 5 API `/tracking-formats`. Chống trùng theo mã tracking đã khớp. Danh sách hãng của phiên mở rộng thành 10 loại. Chạy `npm run db:init`, khởi động lại server, tải lại web; app iPhone không cần build lại.
- **Một tem nhiều mã tracking, mọi phiên quét được mọi hãng**: bỏ giới hạn hãng theo phiên; chỉ cần 1 trong tối đa 3 mã trên tem có trong Danh sách mặt hàng, hiển thị hãng của mã khớp. Thêm cột `scanned_items.product_id` và tham số `alt_barcodes`. Chạy `npm run db:init`, khởi động lại server, tải lại web và **build lại app iPhone** (⚙️ → Bản app: "tem nhiều mã tracking").
- **Mỗi mặt hàng tối đa 3 mã tracking**: thêm cột `products.alt_code2` (+ cột chuẩn hóa `alt2_norm`); form thêm/sửa mặt hàng có 2 ô mã khác; bảng kiện của phiên hiện "Mã khác". Chạy `npm run db:init`, khởi động lại server, tải lại web.
