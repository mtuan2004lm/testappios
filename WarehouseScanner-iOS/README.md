# Kho Scanner (iOS) – kết nối với web Warehouse Tina

App Swift/SwiftUI (iOS 16+) dùng camera iPhone **thay máy quét barcode**. Phiên nhận hàng được tạo trên web; app chỉ chọn phiên đang mở rồi quét, mọi dữ liệu gửi về web qua API:

**Một màn hình quét duy nhất, tự động:** đưa nhãn vào khung *một lần*, app lấy cùng lúc **mã vạch** và **dòng mã kho in trên nhãn** (OCR), tự khớp quy tắc của web rồi gửi `POST /receiving/sessions/:id/scan` (kèm `barcode` + `detected_text`). Không hỏi xác nhận; nhãn nào không đọc đủ cả hai trong ~2 giây thì bỏ qua và quét nhãn kế tiếp. Màn hình chỉ hiển thị nhãn **thuộc kho nào** (không phân loại kinh doanh). Mất mạng thì tự giữ lại và gửi lại mỗi 4 giây. Nút **Báo hỏng** (tuỳ chọn) chụp ảnh gắn vào kiện vừa gửi.

## 1. Chạy server (máy tính)
```bash
cd ../warehouse-receiving/server
npm run db:init        # tạo thêm bảng mới (ảnh hỏng, tracking)
npm run dev
```
Server in ra dòng `Dien thoai dung dia chi: http://192.168.x.x:3000`. Nếu macOS hỏi "cho phép node nhận kết nối đến" → **Allow**. iPhone và máy tính phải cùng Wi-Fi.

## 2. Mở project Xcode
**Cách đơn giản nhất:** thư mục này đã có sẵn `WarehouseScanner.xcodeproj` → bấm đúp để mở (không cần cài thêm gì), rồi làm bước 3.

Nếu muốn tự sinh lại project:
Cách A (nhanh, khuyên dùng):
```bash
brew install xcodegen
cd WarehouseScanner-iOS
xcodegen generate
open WarehouseScanner.xcodeproj
```
Cách B (thủ công): Xcode → New Project → iOS App (SwiftUI, tên `WarehouseScanner`) → xoá `ContentView.swift` và file `...App.swift` mặc định → kéo toàn bộ file trong thư mục `WarehouseScanner/` vào project. Trong tab **Info** của target thêm: `NSCameraUsageDescription`, `NSLocalNetworkUsageDescription`, và `App Transport Security Settings → Allow Arbitrary Loads = YES`. Trong Build Settings: Swift Language Version = **5**, *Default Actor Isolation* = **nonisolated** (nếu có).

## 3. Chạy trên iPhone thật
1. Cắm iPhone, bật **Developer Mode** (Cài đặt → Quyền riêng tư & Bảo mật → Chế độ nhà phát triển).
2. Xcode → target `WarehouseScanner` → **Signing & Capabilities** → chọn Team (Apple ID cá nhân là đủ).
3. Chọn iPhone ở thanh trên, bấm ▶︎. Lần đầu: Cài đặt → Cài đặt chung → VPN & Quản lý thiết bị → tin cậy nhà phát triển.
4. Trong app: ⚙️ → nhập `http://<IP máy tính>:3000` → **Kiểm tra kết nối** (tải 4 nhóm quy tắc mã kho).

## Cấu trúc code
| File | Việc |
|---|---|
| `CameraEngine.swift` | Camera liên tục: barcode (AVFoundation) + OCR (Vision, ~2 khung/giây) |
| `AutoScanViewModel.swift` | Gom mã vạch + mã kho trong cửa sổ 2 giây, gửi nền, bỏ qua nhãn lỗi, tự gửi lại |
| `AutoScanView.swift` | Màn hình quét: hiện kho của nhãn vừa quét |
| `RuleMatcher.swift` | Khớp regex như server + sửa lỗi OCR (`_` bị mất, `0`/`O`) |
| `APIClient.swift` | Gọi API web |

## Kết quả hiển thị trên màn quét
- **Thẻ xanh "KHO …"**: mã có trong *Danh sách mặt hàng* của web, kèm nhóm kho đọc từ nhãn.
- **Thẻ cam "KHÔNG XÁC ĐỊNH"**: mã không có trong Danh sách mặt hàng. Mã vẫn được gửi về web và ghi là *Không xác định*.
- **Thẻ xám "BỎ QUA"**: không đọc đủ mã vạch + mã kho, hoặc mã đã quét trong phiên.

## Lưu ý khi cập nhật
Sau khi sửa code Swift: Xcode → **Run** lại để cài bản mới lên iPhone. Sau khi sửa server: `Ctrl+C` rồi `npm run dev` lại. Xem thêm lịch sử cập nhật trong `../warehouse-receiving/README.md`.
