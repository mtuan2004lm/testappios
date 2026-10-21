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
- Rule "chỉ nhận mã có trong danh sách" nằm **dạng comment** trong `scanController.js` (tìm `RULE AN`, mặc định tắt, không có nút). Bỏ comment khối đó = mã lạ bị từ chối `422 TRACKING_NOT_FOUND` và tính **FAIL**; để comment = mã lạ → TING / **NO NAME**.
- Nguyên tắc 3 trạng thái (mặc định): **FAIL** = không đọc được (label bị che/mờ); **NO NAME** = đọc được nhưng không có trong danh sách; **SUCCESS** = có trong danh sách.
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

### 2026-10-19 · ⭐🔥📱 OCR mã kho: đọc được chữ nhỏ trên tem
- Lỗi: tem in rõ nhưng app lúc bắt lúc không bắt mã kho (vd. "FD VAT HUE" nằm trong khối SHIP TO). Nguyên nhân: (1) Vision mặc định **bỏ qua chữ thấp hơn ~3% chiều cao ảnh**, mà mã kho trên tem chỉ ~1,5–2%; (2) chỉ 1/8 khung hình đọc kỹ (`.accurate`), còn lại `.fast` thường sót chữ nhỏ; (3) cửa sổ đọc chỉ 1 giây.
- `CameraEngine.swift`: thêm `request.minimumTextHeight = 0.012`; đọc kỹ xen kẽ mỗi 2 khung (trước là mỗi 8 khung).
- `AutoScanViewModel.swift`: cửa sổ đọc một tem `window` 1,0 → 1,4 giây (đọc kỹ chậm hơn nên cần dư thời gian).
- Không đổi quy tắc mã kho (vẫn neo đầu dòng, không nhận "SHIP TO/DELIVERY TO"). Không giả định vị trí cố định của mã kho trên tem.
- 🧪 Chưa test trên máy thật (sandbox không chạy được camera/Vision); cần build lại app 📱 và thử các tem. Nếu vẫn sót thì thử đưa tem lại gần hơn hoặc xem hướng đọc theo vùng.

### 2026-10-19 · ⭐🔥📱 Quét cả nhóm mã trên một tem một lần (tối đa 3), server chọn mã có trong danh sách
- Cách cũ: mỗi lần gọi scan = 1 mã, chưa có thông tin thì "ting", đủ 3 mã phải quét END CODE. Cách mới: app gom các mã thấy **cùng lúc trong khung** (chờ tối đa ~0,7 giây) rồi gửi **một lần**; server thử từng mã với Danh sách mặt hàng.
- `scanController.js`: nhận thêm `other_barcodes` (mảng, tối đa 2 mã nữa, bỏ trùng/ký tự lạ/END CODE). Có mã trong danh sách → **SUCCESS** (mã đó là mã gốc, các mã còn lại lưu vào "Tracking trên tem"). Không mã nào có trong danh sách → **NO NAME ngay**, lưu tất cả mã, không cần quét END CODE.
- Giữ nguyên làm dự phòng: gửi **1 mã** mà không có trong danh sách vẫn "ting" (TRACK), đủ 3 mã vẫn bắt quét END CODE như cũ. Rule "chỉ nhận mã có trong danh sách" (`RULE AN`) vẫn đang comment = **mã nào cũng quét được** để test thực tế.
- `APIClient.swift`: `scan(..., others:)` gửi `other_barcodes`. `AutoScanViewModel.swift`: gửi cả nhóm mã một lần và chờ ngắn trong `tryComplete()` để các mã cùng tem kịp vào khung. 📱 cần build lại app.
- 🧪 Đã test sandbox (6 trường hợp): mã chính lạ + mã phụ có trong DS → SUCCESS; mã chính có trong DS → SUCCESS; 3 mã lạ → NO NAME; 1 mã lạ → TING; có 1 mã chờ + 2 mã lạ → NO NAME gồm cả 3; mã phụ trùng mã chính → coi như 1 mã (TING). Chưa chép về máy.

### 2026-10-19 · ⭐ Web: danh sách phiên tự cập nhật (kết thúc/tạo phiên từ iPhone hiện ngay)
- Lỗi: bấm **Kết thúc phiên** trên điện thoại nhưng web phải reload mới thấy. Nguyên nhân: trang **Danh sách phiên** (`SessionList.vue`) chỉ tải 1 lần khi mở, không có cập nhật tự động (trang quét `SessionScan.vue` thì đã tự cập nhật mỗi 1 giây).
- `SessionList.vue`: tự tải lại mỗi 1,5 giây (chạy ngầm, không nháy màn hình, giữ nguyên trang đang xem); dừng khi rời trang.
- Chép web: cần build lại giao diện (`npm run build` trong `client`) hoặc đang chạy `npm run dev` thì tự nhận. Không cần build app iPhone.

### 2026-10-19 · ⭐🔥📱 App iPhone: ô "Mã kho" không bao giờ hiện mã tracking
- Lỗi: thẻ SUCCESS hiện tracking ở ô **MÃ KHO** (app lấy chữ `text` gửi lên để hiện khi server không trả mã kho). Server vẫn trả `detected_warehouse_code = null` đúng.
- `AutoScanViewModel.swift` (sau khi gửi thành công): ô Mã kho = mã kho server trả về, hoặc chữ app đã khớp **quy tắc** (có Nhóm KH) và không trùng tracking; còn lại để "—". Tracking luôn chỉ nằm ở dòng mã tracking.
- Quyết định: **quy tắc mã kho KHÔNG nhận tiền tố "SHIP TO / DELIVERY TO"** (quy tắc vẫn neo đầu dòng `^`). Mã kho phải đứng đầu dòng OCR; chữ mờ/không đọc được thì ô Mã kho để "—".
- 🧪 Chưa chép về máy; cần build lại app 📱.

### 2026-10-19 · ⭐🧪📱 Thêm lại quy tắc "chỉ nhận mã có trong danh sách" dạng comment (ẩn)
- `scanController.js`: khối từ chối `422 TRACKING_NOT_FOUND` (tăng `fail_count`) đặt **trong comment** (`RULE AN`), ngay trước bước ghi TING. Không cần xoá rule hiện tại vì khối này chạy trước.
- `AutoScanViewModel.swift`: nhận `TRACKING_NOT_FOUND` thì báo FAIL đỏ (nhớ 8 giây). 📱 cần build lại app để thấy.
- Bật: bỏ comment khối đó rồi khởi động lại server. Không thêm nút nào vào giao diện.
- 🧪 Đã test sandbox (bản tạm đã bỏ comment): mã có trong danh sách → SUCCESS; mã lạ → 422 + `fail_count` tăng. Để comment: mã lạ vẫn NO NAME.

### 2026-10-19 · ⭐📱 App iPhone: chi tiết phiên (cập nhật 1 giây) + đổi ngôn ngữ Việt/Anh
- **Màn chi tiết phiên** `SessionDetailView.swift` (mới): hiện ĐÃ QUÉT / DỰ KIẾN, danh sách đơn đã quét (mã, nhóm KH, mã kho, nhãn SUCCESS / NO NAME / HỎNG / GIỮ / BLOCK / KHÔNG XÁC ĐỊNH) và nút **Bắt đầu quét** / **Tiếp tục quét** nằm riêng ở đáy. Tự hỏi server mỗi **1 giây** (GET `/receiving/sessions/:id`, cùng lệnh web dùng) nên đơn xoá/thêm/đổi trạng thái trên web hoặc máy khác hiện ngay; mất mạng thì giữ danh sách và thử lại. Nút "Kết thúc phiên" ở góc trên.
- **Luồng mới**: danh sách phiên → (chạm phiên hoặc tạo phiên xong) → chi tiết phiên → Bắt đầu quét → màn quét → nút back về chi tiết phiên.
- `AutoScanView.swift`: ô ĐÃ GỬI lấy số đã quét từ server mỗi 1 giây (và ngay sau mỗi lần quét), nên khớp web.
- `APIClient.swift` (`sessionDetail`), `Models.swift` (`SessionItem`, `SessionDetail`), `SessionsView.swift` (đi vào chi tiết phiên).
- **Đổi ngôn ngữ VI/EN**: `Localization.swift` (mới) có `tr("câu tiếng Việt")` và bảng dịch tiếng Anh (~110 câu); mọi chuỗi trong app đã bọc `tr(...)`. Công tắc **VI | EN** ở màn đăng nhập và mục *Ngôn ngữ / Language* trong ⚙️ Cài đặt; lựa chọn được nhớ (`UserDefaults` khoá `lang`), đổi là có hiệu lực ngay. Dữ liệu từ web (tên hãng, mặt hàng, nhóm KH, mô tả định dạng) không dịch. 🔥 Thêm chữ mới trong app: viết `tr("câu tiếng Việt")` rồi thêm bản tiếng Anh vào bảng `L10n.en`, nếu không sẽ hiện tiếng Việt khi chọn English. Khoá `{0}`, `{1}` là chỗ thay giá trị.
- `AppStore.swift`: đổi dấu bản build (⚙️ → Bản app: "giao diện quét mới + tạo/kết thúc phiên + VI/EN"). Sửa: `project.pbxproj` thêm `SessionDetailView.swift`, `Localization.swift`.
- Server/web không đổi. Chưa build thử (sandbox không có Swift). Bản cũ để quay lại: `WarehouseScanner-iOS/_old/*.before-i18n`.

### 2026-10-19 · ⭐📱 App iPhone: tạo phiên, dừng quét (chốt kiện), kết thúc phiên
- `NewSessionView.swift` (mới): form giống web "Bắt đầu phiên mới" (đơn vị vận chuyển, cửa kho, người giao, biển số, số kiện); mở từ nút ➕ ở danh sách phiên, tạo xong vào quét ngay.
- `AutoScanView.swift`: nút ⋯ ở hàng dưới → "Dừng quét (chốt kiện)" (PATCH `/finalize`, dừng camera, màn "ĐÃ DỪNG QUÉT" có Tiếp tục quét / Kết thúc phiên) và "Kết thúc phiên" (PATCH `/close`, rồi về danh sách). Cả hai đều hỏi xác nhận.
- `APIClient.swift`: thêm `createSession`, `finalizeSession`, `closeSession`. `SessionsView.swift`: nút ➕. `project.pbxproj`: thêm `NewSessionView.swift`.
- Server không đổi. Bản cũ để quay lại: `WarehouseScanner-iOS/_old/*.before-sessions`.

### 2026-10-19 · ⭐📱 App iPhone: giao diện quét mới (chung cho iPhone Pro và Pro Max)
- `AutoScanView.swift`: ô **ĐÃ GỬI** to ở trên cùng, thẻ SUCCESS/FAIL/... ngay dưới nó (chừa sẵn chỗ cao 200 để khung quét không nhảy), khung quét co giãn ở giữa, hàng dưới: nút quay lại + BỎ QUA + FAIL (nhỏ), rồi hàng nút đèn pin / Ảnh label / Hỏng / danh sách. Bỏ dòng "Quét lần lượt tracking…" và thanh tiêu đề trên cùng (nút quay lại giờ ở dưới).
- 🔥 Mã tracking/mã kho không rớt dòng: `lineLimit(1)` + `minimumScaleFactor(0.5)`; mã dài hơn 40 ký tự thì cắt phần giữa. Không dùng kích thước pixel cố định nên Pro (393) và Pro Max (440) cùng bố cục.
- `Extensions.swift` (Reticle): khung quét điền đầy vùng giữa.
- Bản cũ để quay lại: `WarehouseScanner-iOS/_old/AutoScanView.swift.before-newui`, `Extensions.swift.before-newui`.

### 2026-10-19 · ⭐📱 App iPhone: thêm màn hình đăng nhập (bản thử, chưa nối API công ty)
- File mới: `LoginView.swift` (giao diện đăng nhập), `AuthStore.swift` (trạng thái đăng nhập; chỉ nhớ email + cờ đã đăng nhập, **không lưu mật khẩu**).
- Sửa: `WarehouseScannerApp.swift` (chưa đăng nhập → LoginView), `SettingsView.swift` (mục Tài khoản + Đăng xuất), `project.pbxproj` (thêm 2 file).
- Sửa lỗi build: `AuthStore.init` đọc `userEmail` trước khi khởi tạo xong ("used before being initialized") → dùng biến tạm `saved`.
- Bản thử: chỉ cần bấm "Đăng nhập" là vào, không bắt nhập email/mật khẩu (bỏ trống → tài khoản "Khách (bản thử)"). Khi nối API phải bật lại kiểm tra ô trống.
- 🔥 `AuthService.signIn` hiện không kiểm tra gì, cho vào luôn. Khi nối API công ty, thay thân hàm này bằng POST `/auth/login` và lưu token vào Keychain.

### 2026-10-15 · ⭐ Web: chọn và xoá kiện đã quét / nhập tay
- Màn hình quét có cột **checkbox** (chỉ khi phiên đang mở) + ô chọn tất cả; chọn xong hiện nút **"Xoá đã chọn (n)"** (có hỏi xác nhận).
- Server: `POST /api/v1/receiving/sessions/:id/items/delete` body `{ "ids": [..] }` (`itemController.deleteItems`). 🔥 Xoá trong 1 transaction: kiện + ảnh (DB và file) + **các dòng `label_scans` của kiện đó** (nếu để lại, tracking sẽ thành "đang chờ" và dính vào kiện kế tiếp), rồi tính lại `scanned_count`.
- Chỉ xoá được kiện của phiên **đang mở** (phiên đóng → 409 `SESSION_CLOSED`); tối đa 500 kiện/lần. Không hoàn tác được.
- `api.js` thêm `deleteItems`; `en.js` thêm 7 câu dịch.
- 🧪 Đã test: xoá 2/3 kiện, xoá lại kiện đã xoá (404), ids rỗng (400), phiên đóng (409), không còn `label_scans` mồ côi, giao diện VI/EN.

### 2026-10-14 · ⭐ Web: đổi ngôn ngữ Tiếng Việt / English
- Navbar có nút **VI | EN** (biểu tượng quả địa cầu). Lựa chọn lưu trong `localStorage` (khóa `lang`), tải lại trang vẫn giữ.
- `client/src/i18n.js` (mới): `tr(key, ...args)` — khóa là **câu tiếng Việt gốc**, `{0}` là chỗ chèn biến; thiếu bản dịch thì hiện tiếng Việt. `trMsg()` dịch thông báo lỗi/cảnh báo từ server (từ điển + mẫu regex). `locale()` đổi định dạng ngày giờ vi-VN / en-US.
- `client/src/locales/en.js` (mới): ~410 câu tiếng Anh. 🔥 Thêm chữ mới trong web → bọc `tr('...')` và thêm dòng vào `en.js`.
- Đã bọc toàn bộ view + navbar + `api.js`. Danh sách nhãn hằng số dùng getter để đổi ngôn ngữ là cập nhật ngay.
- Không đổi: dữ liệu người dùng nhập/DB (tên mặt hàng, mô tả định dạng tracking...). Server và app iOS không đổi.
- 🧪 Đã test Playwright: 9 trang ở chế độ EN không còn chữ Việt (ngoài dữ liệu DB), không lỗi console.

### 2026-10-14 — ⭐🗄️🧪 Kiện NO NAME tự có ngoại lệ "Không xác định" (trước đây là "Bình thường")
- **Vì sao:** NO NAME và "Không xác định" trước đây lưu tách riêng; kiện NO NAME mặc định ngoại lệ "Bình thường" nên không được đếm / tô đỏ như Không xác định. Chọn phương án 2: NO NAME tính là Không xác định (nhãn tím NO NAME vẫn hiện để phân biệt).
- **Sửa (`scanController.js` → `makeItem`):** `exception_status` = `UNKNOWN` khi `noName`, ngược lại `NORMAL`. Khi sau này gán được mã kho cho kiện thì ngoại lệ tự về Bình thường (logic cũ giữ nguyên). Cần khởi động lại server.
- **Dữ liệu cũ (🗄️):** `server/scripts/fix-noname.js` (`npm run db:fix-noname`) đổi mọi kiện NO NAME đang "Bình thường" sang "Không xác định"; kiện đã đổi tay sang Hư hỏng / Đang giữ / Bị chặn giữ nguyên; chạy lại an toàn.
- Đã test sandbox: quét 3 tracking không thông tin + END CODE → `is_no_name = true`, `exception_status = UNKNOWN`; script đổi đúng 1 kiện.
- Lưu ý: bộ đếm "Không xác định" và "No Name" trên web giờ có thể cùng đếm một kiện (đúng ý phương án 2).

### 2026-10-14 — 🧪 "Không xác định" hiện chữ đỏ
- `client/src/views/SessionScan.vue`: dòng đếm "Không xác định" ở khung thống kê (icon + chữ đậm đỏ); ô chọn Ngoại lệ của từng kiện khi đang là "Không xác định" (chữ đậm đỏ, viền đỏ nhạt). Chỉ đổi giao diện web, không cần khởi động lại server (chỉ tải lại trang).

### 2026-10-14 — ⭐🧪 Sửa: thẻ SUCCESS trên web hiện tracking ở dòng "Mã kho" (UPS 1Z…, Amazon TBA…)
- **Triệu chứng:** quét label UPS / Amazon (TBA) không đọc được mã kho thì thẻ SUCCESS ở màn hình quét web vẫn ghi "Mã kho: <mã tracking>", Nhóm KH "—".
- **Nguyên nhân:** dữ liệu **lưu** đã đúng (cột mã kho để trống), nhưng `successResponse` ghi `receiving_sessions.last_scan_text = mt`, mà `mt` có phương án dự phòng là chính tracking → thẻ web (đọc từ `last_scan_text`) hiện tracking như mã kho.
- **Sửa (`scanController.js`):** `last_scan_text` = `item.detected_warehouse_code` (mã kho thật đã lưu, hoặc trống). Cần khởi động lại server.
- Đã test sandbox: quét `1Z44016X0393539152` không kèm chữ → `last_scan_text = null`; kèm "FD VAT HUE" → "FD VAT HUE" / FADO.VN.
- **Còn lại:** nếu Nhóm KH vẫn "—" thì do app chưa đọc được chữ mã kho trên tem (OCR) hoặc quy tắc chưa khớp (xem mục FD VAT HUE cùng ngày). Với label Amazon TBA, dòng "SGHUE DOFA" rất nhỏ, cần để tem gần camera hơn.

### 2026-10-14 — ⭐🗄️🧪 Sửa quy tắc mã kho FADO.VN: nhận "FD VAT HUE" (có khoảng trắng)
- **Triệu chứng:** label có mã kho "FD VAT HUE" nhưng app/web không nhận (Nhóm KH trống), tracking còn hiện ở cột Mã kho.
- **Nguyên nhân:** quy tắc mặc định `^(FDVAT HUE|SGHUE DOFA|HNBANGTY DOFA|SG FRAGILE DOFA|HN FRAGILE DOFA)` viết dính chữ (FDVAT) trong khi nhãn in "FD VAT HUE". OCR đọc đúng nhưng không khớp regex.
- **Sửa:** quy tắc mới `^(FD ?VAT ?HUE|SG ?HUE DOFA|HN ?BANGTY DOFA|SG ?FRAGILE DOFA|HN ?FRAGILE DOFA)` (khoảng trắng tùy chọn). Thêm `server/scripts/fix-rules.js` (`npm run db:fix-rules`): chỉ sửa khi quy tắc còn là bản mặc định cũ, chạy lại nhiều lần vẫn an toàn; `schema.sql` đã đổi seed cho database mới.
- **Cách dùng (🗄️):** `cd server && npm run db:fix-rules`, rồi tắt/mở lại app iPhone (app tải quy tắc khi mở), rồi nếu cần `npm run db:recompute` để tính lại kiện cũ (lưu ý lệnh này tính lại cả loại hình, ghi đè chỉnh tay; muốn chỉ dọn tracking nhầm thì dùng `-- --clear-only`).
- Đã test trên sandbox: "FD VAT HUE", "FDVAT HUE", "fd vat hue" đều khớp FADO.VN; "FD VAT" và chuỗi tracking UPS không khớp.

### 2026-10-14 — ⭐🔥📱🧪 Sửa lỗi "đưa tem vào mà không quét, phải che camera mới quét lại" (thử nghiệm, có thể quay lại)
- **Nguyên nhân:** app nhớ mọi mã đã gửi; tem đã quét còn trong khung (hoặc rời khung chưa tới 1,5 giây rồi quay lại) thì bị bỏ qua **âm thầm** — không báo gì, nhìn như app hỏng. Che camera >1,5 giây làm app coi tem đã rời khung. Ngoài ra, khi tem cũ còn sót một phần trong khung, app chặn 2 giây chữ mã kho nên tem mới bị nuốt mã kho.
- **Sửa (`AutoScanViewModel.swift`):** (1) thêm `hint` + `showHint` hiện lý do im lặng ("Tem này đã quét rồi — đưa ra khỏi khung rồi đưa lại để báo trùng", "Tem này vừa báo lỗi — đợi vài giây rồi đưa lại"); (2) thời gian "tem rời khung" để quét lại 1,5 → **0,7 giây**; (3) `hasNew`: khi trong khung có tem mới thì tem cũ **không** chặn / xóa chữ mã kho nữa, và `suppressTextUntil` được hủy khi tem mới vào.
- **Sửa (`AutoScanView.swift`):** hiện `vm.hint` dưới thanh thông báo. `AppStore.buildTag` đã đổi.
- 🧪 Swift chưa build thử ở sandbox → thử trên máy thật.
- **Quay lại bản cũ nếu không ổn:** bản trước nằm ở `WarehouseScanner-iOS/_backup_truoc_2026-10-14/` (3 file). Chạy:
  `cd WarehouseScanner-iOS && cp _backup_truoc_2026-10-14/*.swift WarehouseScanner/` rồi build lại.

### 2026-10-14 — 📱🧪 Khung quét to hơn (chỉ là khung hướng dẫn trên màn hình)
- `Extensions.swift` → `Reticle`: khung cố định 320×200 đổi thành rộng gần hết màn hình (chiều rộng − 24, cao ≈ 0,8 × rộng, tối đa 55% chiều cao màn hình).
- **Lưu ý:** khung chỉ để căn nhãn. Camera **đọc toàn bộ khung hình** cho cả mã vạch lẫn OCR từ trước đến nay, nên khung to hơn **không tự làm quét nhanh hơn**; tốc độ phụ thuộc khoảng cách/độ nét (xem mục 2026-10-13). Chưa build thử Swift trên sandbox.

### 2026-10-13 — ⭐🧪📱 Quét nhanh hơn ~2 lần + tự lấy nét lại khi camera kẹt (phải che camera mới quét lại)
- **Triệu chứng:** thỉnh thoảng camera không đọc được tem, phải che camera đi rồi mới nhận lại; tốc độ quét chưa cao.
- **Nguyên nhân khả dĩ:** camera kẹt lấy nét/phơi sáng (che camera buộc nó lấy nét lại); ngoài ra OCR bị giới hạn ~8 lần/giây vì có khoảng nghỉ 0,1 giây và cứ 4 lần có 1 lần đọc kỹ (chậm).
- **Sửa (`CameraEngine.swift`):** bỏ khoảng nghỉ 0,1 giây giữa hai lần OCR (khung này xong là đọc khung kế); đọc kỹ 1/8 khung thay vì 1/4; **tự lấy nét + đo sáng lại** khi OCR thấy chữ (tem đang trong khung) nhưng >1,5 giây không đọc được mã vạch (tối đa 2 giây/lần, sau 0,4 giây trở lại lấy nét liên tục).
- **Sửa (`AutoScanViewModel.swift`):** cửa sổ đọc một tem 1,5 → **1,0 giây**; đồng hồ cập nhật mỗi 50 ms (trước 100 ms); mã kho đọc trước đó còn hiệu lực 1,0 giây (trước 1,5).
- **Lưu ý 🧪:** Swift chưa build thử được trên sandbox; cần thử trên ~30-50 tem thật. Cửa sổ ngắn hơn có thể làm tăng số tem "thiếu mã kho" → nếu thấy nhiều thì đổi `window` về 1,5. Chưa hứa đúng "gấp 2" — số đo thật phải đo trên máy.
- `AppStore.buildTag` đã đổi để nhận biết bản mới.

### 2026-10-13 — Tài liệu: thêm mục "Công nghệ sử dụng" vào README
- `README.md` có mục mới liệt kê công nghệ của database (PostgreSQL), server (Node 22, Express 4, pg), web (Vue 3, Vite, Tailwind, ZXing), app iPhone (Swift/SwiftUI, AVFoundation, Vision, XcodeGen) và công cụ (Playwright, draw.io). Không đổi code.

### 2026-10-12 — ⭐🔥 Sửa lỗi: tracking bị lưu nhầm thành "Mã kho" (cột Nhóm KH / Mã kho hiện "—" kèm mã tracking)
- **Nguyên nhân:** mã vạch USPS GS1-128 chứa ký tự điều khiển ẩn `GS` (0x1D). Server đã lọc ký tự này khỏi `barcode` nhưng **không lọc khỏi `detected_text`** → hai chuỗi lệch nhau → server tưởng chuỗi đó là "mã kho đọc từ nhãn" và lưu tracking vào `detected_warehouse_code`; vì không khớp quy tắc nên Nhóm KH trống ("—"). Xảy ra với quét bằng web (web gửi `detected_text = barcode`) và mọi trường hợp chuỗi gửi lên là chính tracking.
- **Sửa (`server/controllers/scanController.js`):** `detectedText` được lọc ký tự điều khiển giống `barcode`; so sánh barcode ↔ mã kho bỏ khoảng trắng / không phân biệt hoa thường (`squash`); `makeItem` coi chuỗi là **không phải mã kho** nếu trùng tracking của kiện, tracking khớp, hoặc Tracking / Mã khác 1 / Mã khác 2 của mặt hàng.
- **Dọn dữ liệu cũ (`server/scripts/recompute-items.js`):** `npm run db:recompute -- --clear-only` — chỉ xóa "mã kho" thực chất là tracking (trùng barcode hoặc chỉ gồm ≥10 chữ số, không khớp quy tắc nào); **không** tính lại Nhóm KH / Loại hình nên không mất chỉnh sửa tay. (`npm run db:recompute` không kèm cờ vẫn tính lại tất cả như cũ.) Đã test: kiện lỗi được xóa mã kho, kiện có nhóm chỉnh tay giữ nguyên.
- 🔥 Lưu ý: kiện quét bằng **web / máy quét** không đọc được chữ trên tem nên vẫn không có Nhóm KH / Mã kho (hiện "—"); chỉ app iPhone (OCR) đọc được mã kho in trên tem.
- Không đổi schema. Cần khởi động lại server.

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
