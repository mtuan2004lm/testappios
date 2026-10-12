# NHẬT KÝ THAY ĐỔI — Hệ thống nhận hàng TinaShipping · OR_1 Hub Oregon

> File này ghi lại **mọi thay đổi trong code**: tính năng mới, sửa lỗi, đổi quy tắc, và những phần quan trọng / khó.
> **Quy tắc:** mỗi khi sửa bất kỳ thứ gì trong code (server, web, app iOS, database), phải thêm một mục mới vào đây (mới nhất ở trên cùng của phần "Lịch sử").

**Ký hiệu**
- ⭐ = quan trọng (ảnh hưởng cách hệ thống hoạt động hoặc cách dùng)
- 🔥 = khó / dễ sai (cần đọc kỹ trước khi sửa lại phần này)
- 🧪 = chỉ để test (có thể bật/tắt)
- 📱 = cần build lại app iPhone trong Xcode mới có hiệu lực
- 🗄️ = cần chạy lại `npm run db:init` (đổi database)

---

## 1. Bản đồ code (file nào làm việc gì)

| Khu vực | File | Vai trò |
|---|---|---|
| Database | `server/schema.sql` | Toàn bộ bảng, cột, index. Chạy lại bằng `npm run db:init` (an toàn, không mất dữ liệu) |
| Quét | `server/controllers/scanController.js` | ⭐🔥 Trái tim hệ thống: xử lý từng mã quét (tuần tự 3 tracking, END CODE, NO NAME, block) |
| So khớp mã | `server/utils/trackingFormats.js` | Khớp tracking với Danh sách mặt hàng (EXACT / DERIVED / CONTAINS, ZIP+4) |
| Phiên | `server/controllers/sessionController.js` | Trả thông tin phiên + danh sách kiện + bộ đếm ngoại lệ cho web |
| Kiện | `server/controllers/itemController.js` | Ảnh hỏng, ảnh label, đổi trạng thái ngoại lệ |
| Mặt hàng | `server/controllers/productController.js` | Danh sách mặt hàng (tracking + mã khác 1 + mã khác 2) |
| Hàng giữ / Block | `server/controllers/holdController.js`, `server/utils/blocks.js` | Hold kho và Block do khách yêu cầu (8 lý do) |
| Web quét | `client/src/views/SessionScan.vue` | ⭐ Màn hình quét + lịch sử quét + thẻ trạng thái |
| Web mặt hàng | `client/src/views/ItemsList.vue` | Quản lý Danh sách mặt hàng |
| Web hàng giữ | `client/src/views/HoldsList.vue` | Hàng đang giữ + Block |
| API client | `client/src/api.js` | Hàm gọi server |
| QR END CODE | `client/public/end-code-qr.png` | Mã QR cố định nội dung `END CODE` |
| App iPhone | `WarehouseScanner-iOS/WarehouseScanner/` | `AutoScanViewModel.swift` (logic quét), `AutoScanView.swift` (giao diện), `APIClient.swift`, `Models.swift`, `AppStore.swift` |
| Sơ đồ DB | `Database_He_thong_nhan_hang.drawio` | ERD mở bằng draw.io |

---

## 2. Những điểm khó / quan trọng cần nhớ

### ⭐🔥 Mô hình quét tuần tự (mỗi lần gọi scan = 1 mã)
- `POST /receiving/sessions/:id/scan` chỉ xử lý **một mã**. Một tem có tối đa **3 tracking**.
- Kết quả trả về:
  - `SUCCESS` (201, tiếng **yes**): mã có trong Danh sách mặt hàng → ghi nhận 1 kiện.
  - `TRACK` (200, tiếng **ting**, `seq` 1..3): mã chưa có thông tin → lưu vào `label_scans` (chưa gắn kiện), chờ mã tiếp theo.
  - `NO_NAME` (201, tiếng **ting**): quét QR END CODE sau khi đủ tracking không có thông tin → tạo kiện NO NAME, lấy tracking đầu làm tracking gốc.
  - Lỗi 409: `END_CODE_REQUIRED` (đủ 3 tracking chưa có thông tin mà không quét END CODE), `NO_PENDING_TRACKS` (quét END CODE khi không có gì đang chờ), `DUPLICATE_BARCODE` (chỉ khi bật chặn trùng).
- "Có thông tin" = mã có trong **Danh sách mặt hàng** (khớp tracking / mã khác 1 / mã khác 2).
- Tracking đang chờ lưu trong `label_scans` với `item_id = NULL`; khi kiện được tạo thì gắn `item_id`.

### ⭐ END CODE
- Là **1 mã QR cố định dùng chung**, nội dung `END CODE`. Regex nhận dạng: `/^END[\s_-]?CODE$/i`.
- Quét thiếu END CODE mà quét mã khác → web hiện pop-up chặn bắt buộc quét END CODE.
- Nút web "Chốt kiện - END CODE" là **chốt số kiện của phiên**, KHÔNG phải QR END CODE (dễ nhầm; đã đề xuất đổi tên thành "Chốt số kiện").

### 🔥 So khớp mã (`trackingFormats.js`)
- Các cột `tracking_norm`, `alt_norm`, `alt2_norm` trong `products` là cột **tự sinh** (bỏ khoảng trắng, viết hoa) — đừng ghi trực tiếp.
- Mã ZIP+4 (vd `420xxxxxyyyy` hoặc `xxxxxyyyy`) được thử thêm ở dạng có gạch `xxxxx-yyyy`.
- Hãng vận chuyển **không còn** giới hạn việc quét.

### 🧪 Cờ test
- `BLOCK_DUPLICATES` (biến môi trường, mặc định **tắt**): tắt = quét lại cùng mã vẫn được ghi nhận (để test với ít mã). Bật `BLOCK_DUPLICATES=true` = chặn trùng trong cùng phiên. Quét cùng mã ở phiên khác luôn được.
- Ràng buộc unique `unique_barcode_per_session` đã bị bỏ khỏi schema.

### 🔥 Đồng bộ trạng thái app → web
- Server lưu lần quét gần nhất trong `receiving_sessions.last_scan_*`. Web hỏi server **mỗi 1 giây** và hiện thẻ trạng thái trong khung READY (giữ 8 giây).
- `last_scan_status` rộng 20 ký tự: SUCCESS, FAIL, DUPLICATE, TRACK, NO_NAME.

### 🔥 Khi chạy lại database (`schema.sql`)
- Khối `DO $$ ... $$` đồng bộ sequence **không được liệt kê bảng tạo ở phần sau** của file (đã từng lỗi "relation label_scans does not exist").
- Mọi `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` đều chạy lại an toàn.

### ⭐ App iPhone
- Barcode/QR do `AVCaptureMetadataOutput` đọc; mã kho trên tem do **Apple Vision OCR** đọc. Cửa sổ đọc `window = 1.5` giây.
- Âm thanh dùng system sound ID 1057 (yes), 1103 (ting), 1053 (cảnh báo) — **chưa kiểm chứng trên máy thật**.
- Code Swift **chưa từng được biên dịch** ở môi trường phát triển; luôn build lại trong Xcode và báo lỗi nếu có.
- 🔥 Project Xcode được sinh từ `WarehouseScanner-iOS/project.yml` (XcodeGen) và `.xcodeproj` liệt kê từng file Swift: **mỗi khi thêm file Swift mới** (vd. `PhotoOutbox.swift`) phải chạy `xcodegen generate` trong thư mục `WarehouseScanner-iOS` (hoặc kéo file vào Xcode, tích target) thì app mới biên dịch.

---

## 3. Việc chưa làm / đang chờ

- Phần 2 (Block tracking): **đã làm và test trong sandbox, chưa đưa vào máy** (chờ xác nhận). Chưa làm phần app iPhone cho block (thẻ đỏ + tiếng cảnh báo).
- Phần 3 (NO NAME): giao diện cho nhân viên VN review kiện NO NAME + review ảnh label.
- Quyết định chưa chốt: NO NAME có tự tính vào "Không xác định" không (đang để riêng).
- Có thể làm sau: đổi tên nút "Chốt kiện - END CODE", import CSV cho 3 cột tracking, phân trang lịch sử quét, cập nhật tài liệu API (PDF/Word), thêm bộ đếm đo độ chính xác OCR trong app.

---

## 4. Lịch sử thay đổi (mới nhất ở trên)

### 2026-10-12 — ⭐🔥 📱 Sửa lỗi: ảnh label không được lưu đủ cho mọi kiện trong phiên
- **Các lỗ hổng tìm thấy trong code (bản tự chụp trước đó):**
  1. Ảnh chụp lúc **gửi** (sau cửa sổ đọc 1,5 giây), không phải lúc thấy mã → tem có thể đã rời khung, ảnh sai hoặc trống.
  2. Mất mạng lúc quét: mã được gửi lại sau nhưng ảnh bị chụp lại ở thời điểm khác (hoặc mất).
  3. Gửi ảnh thất bại chỉ báo 3 giây rồi **bỏ**; ảnh chỉ nằm trong bộ nhớ nên thoát màn hình / tắt app là mất.
  4. Kiện quét bằng web không có ảnh và không có cảnh báo gì.
- **Sửa (app):** `AutoScanViewModel.swift` chụp ảnh **ngay khi thấy mã vạch lần đầu** (`shotByCode`, các mã cùng khung dùng chung ảnh) và dùng đúng ảnh đó khi gửi/gửi lại. File mới `PhotoOutbox.swift`: ảnh được **lưu trên ổ đĩa iPhone** (`Documents/PhotoOutbox`), chỉ xóa khi server xác nhận; thử lại mỗi 5 giây; tự gửi bù ảnh còn sót khi vào lại màn quét hoặc mở danh sách phiên (`SessionsView`). Hiện "N ảnh label đang chờ gửi" trên màn quét. Dòng "Bản app" = "ảnh label chụp lúc thấy mã + hàng đợi lưu trên máy".
- **Sửa (web):** `SessionScan.vue` hiện chip đỏ **"⚠ N kiện thiếu ảnh label"** ở đầu lịch sử quét và dòng "⚠ Thiếu ảnh label" ở từng kiện chưa có ảnh (bấm "Ảnh label" ở dòng đó để bổ sung tay).
- 🔥 Còn giới hạn: nếu camera không có khung hình (hiếm) hoặc công tắc tự chụp tắt thì kiện vẫn thiếu ảnh — nhưng nay web sẽ báo rõ. Code Swift chưa biên dịch; web đã kiểm tra bằng Playwright (phiên 26 kiện: báo đúng 25 kiện thiếu).

### 2026-10-12 — 🔥 Sửa lỗi: bấm link "Label"/"Ảnh" trong lịch sử bị nhảy về đầu trang, không mở được ảnh
- **Nguyên nhân:** ô quét tự lấy lại focus mỗi khi mất focus (`@blur → focusInput()`). Bấm vào link làm ô mất focus → `focus()` cuộn trang về đầu (ô quét nằm trên cùng) → link dịch khỏi dưới con trỏ nên lần bấm không kích hoạt, ảnh không mở. Chỉ xảy ra khi trang đã cuộn xuống (nhiều kiện trong phiên).
- **Sửa (`SessionScan.vue`):** `focusInput` dùng `focus({ preventScroll: true })`; `@blur` gọi `refocusUnlessInteractive` — không lấy lại focus khi người dùng vừa bấm vào link/nút/select/input/label khác.
- Đã tái hiện và kiểm tra bằng Playwright (phiên 26 kiện, cuộn xuống rồi bấm Label): code cũ → trang về 0, không mở tab; code mới → mở tab ảnh, giữ nguyên vị trí cuộn.
- 🔥 Lưu ý: bất kỳ nơi nào gọi `focus()` lên ô quét đều nên dùng `preventScroll`.

### 2026-10-12 — ⭐ 📱 App iPhone: tự chụp ảnh label cho từng lần quét
- Mỗi lần quét một mã (tracking, END CODE), app lưu **khung hình camera** ngay lúc đó và gửi lên kiện dưới dạng **ảnh label** (cùng đường `POST /scanned-items/:id/label-photo`, hiện ở mục "Ảnh label" trên web để nhân viên VN kiểm tra). Không cần thêm thay đổi server/web.
- 🔥 Với tem có nhiều tracking: ảnh của các tracking chưa có thông tin được **giữ lại** (`pendingShots`, tối đa 4) rồi gắn vào kiện khi kiện được tạo (SUCCESS hoặc NO NAME), cùng với ảnh của lần quét tạo kiện. Ảnh của lần quét bị lỗi/trùng thì bỏ.
- `CameraEngine.swift`: giữ khung hình mới nhất (`_latest`) và thêm `snapshot()` (xoay đúng chiều, cạnh dài ≤ 1280px, JPEG chất lượng 0,6, chạy luồng nền). `AutoScanViewModel.swift`: chụp song song với lúc gửi server (`shotTask`), gửi ảnh âm thầm bằng `uploadShots`, chỉ báo khi lỗi. `AutoScanView.swift`: gắn `vm.snapshotProvider`.
- **Cài đặt** có công tắc "Tự chụp ảnh label khi quét" (mặc định **bật**, lưu bằng `UserDefaults` khóa `autoLabelShot`). Dòng "Bản app" = "tự chụp ảnh label khi quét".
- Giới hạn: nếu mất mạng lúc quét thì mã được gửi lại sau nhưng **ảnh của lần đó không được gửi**. Code Swift chưa biên dịch — build trong Xcode và báo lỗi nếu có.

### 2026-10-12 — Tạo file nhật ký này
- Thêm `CHANGELOG.md` (file này) và `CLAUDE.md` ghi quy tắc: sửa code là phải cập nhật nhật ký.

### 2026-10-10 — ⭐ Phần 2: Block tracking (🗄️ 📱 một phần) — *đã test trong sandbox, chờ đưa vào máy*
- Block = bản ghi `holds` có `hold_type = 'CUSTOMER'` + 1 trong **8 lý do cố định**: `DAMAGED`, `RETURN`, `STORED_PENDING`, `QTY_VERIFY`, `PHOTO_VIDEO`, `CUSTOMS_SPLIT`, `REPACK`, `PRODUCT_INSPECT` (định nghĩa trong `server/utils/blocks.js`).
- **Schema:** `scanned_items.block_hold_id`, `receiving_sessions.last_scan_block`, index `idx_holds_tracking_active`.
- **Server:** `holdController.create` từ chối lý do ngoài 8 lý do khi là Block; thêm `GET /holds/block-reasons`. `scanController.successResponse` tra block ACTIVE theo mọi mã của kiện (mã quét, tracking trên tem, tracking + mã khác 1/2 của mặt hàng) → trả `blocked`, `block_reason`, `block_reason_label`, `blocks[]`, `sound: 'WARNING'`. **Vẫn ghi nhận kiện** (cảnh báo + ghi nhận).
- 🔥 Cả kiện NO NAME cũng được kiểm block theo các tracking trên tem. Hold kho (`WAREHOUSE`) **không** gây cảnh báo block.
- `sessionController.getSession` trả `block_reason`, `block_status`, `block_reason_label` cho từng kiện.
- **Web:** thẻ đỏ **BLOCK** + tiếng cảnh báo ở khung READY và camera; huy hiệu BLOCK + dòng lý do trong lịch sử (xám + "(đã gỡ)" khi gỡ block); `HoldsList.vue` dùng đúng 8 lý do cho loại Block.
- **Chưa làm:** app iPhone chưa đọc `blocked` (vẫn báo như thành công).
- ⚠ **Đã vào máy một phần:** file `SessionScan.vue` mới (kèm bản sửa ảnh label) đã chứa giao diện BLOCK, nhưng server (`scanController`, `sessionController`, `holdController`, `utils/blocks.js`, `schema.sql`) và `HoldsList.vue` **chưa** vào máy → giao diện BLOCK chưa có tác dụng cho tới khi đưa phần server vào.

### 2026-10-10 — Vẽ sơ đồ database
- Thêm `Database_He_thong_nhan_hang.drawio` (11 bảng, quan hệ khóa ngoại nét liền, liên kết logic nét đứt).

### 2026-10-09 — Tăng tốc hiển thị trạng thái
- Web: hỏi server mỗi **1 giây** (trước là 2 giây) — `SessionScan.vue`, `setInterval(... load(), 1000)`.
- 📱 App: cửa sổ đọc `window` từ 2,0 → **1,5 giây** — `AutoScanViewModel.swift`. Nếu OCR đọc sót mã kho thì tăng lại.

### 2026-10-09 — Bảng lịch sử quét hiển thị đầy đủ
- Giữ ở cột phải, bố cục 4 cột (`table-fixed` + `colgroup` 62px / linh hoạt / 132px / 150px), không cuộn ngang, mã dài tự xuống dòng (`break-all`). Từng bị che một phần do bố cục cũ.
- Hiện "Tracking trên tem", "Mã tracking khác", huy hiệu NO NAME, link ảnh label.

### 2026-10-09 — Tắt chặn trùng để test
- Thêm cờ `BLOCK_DUPLICATES` (mặc định tắt), bỏ unique constraint (🗄️). Cờ test cũ `REQUIRE_IN_LIST` đã gỡ (thay bằng luồng mới).

### 2026-10-09 — ⭐🔥 Phần 1 luật mới: quét tuần tự 3 tracking + END CODE (🗄️ 📱)
- Viết lại `scanController.exports.scan` theo mô hình ở mục 2. Thêm bảng `label_scans`, cột `scanned_items.is_no_name`, `item_photos.kind` (`DAMAGE`/`LABEL`), `last_scan_status` → VARCHAR(20).
- Web: thẻ **TING** (vàng), thẻ **NO NAME** (tím), khung "Tem đang quét", pop-up chặn END CODE kèm ảnh QR và nút nhập tay; âm thanh yes (2 tiếng tăng dần) / ting (1 tiếng cao).
- **Ảnh label**: `POST /scanned-items/:id/label-photo` (không đổi trạng thái ngoại lệ); nút "Ảnh label" trên web và app.
- 📱 App: logic mới trong `AutoScanViewModel.swift` (`pendingTracks`, `endRequired`, cascade các mã thấy cùng khung, END CODE gửi ngay), giao diện `AutoScanView.swift` (lớp chặn, thẻ TING/NO NAME). Dòng "Bản app" trong ⚙️ = "quét tuần tự 3 tracking + END CODE".

### (trước đó) — Tối đa 3 mã tracking cho một mặt hàng (🗄️)
- Thêm `products.alt_code2`; đổi nhãn thành "Mã tracking khác (1)/(2)" trên web; hiện "Mã tracking khác" trong lịch sử. Cột tự sinh `alt2_norm`.

### (trước đó) — So khớp ZIP+4 và không giới hạn theo hãng
- `candidatesFor` thêm các dạng ZIP+4; hãng vận chuyển không còn ngăn việc quét.

### (trước đó) — Tài liệu
- Báo cáo tổng hợp PDF `Bao_cao_tong_hop_he_thong_nhan_hang.pdf`; tài liệu API (PDF/Word) — **bản API chưa cập nhật** các endpoint và trạng thái mới.
