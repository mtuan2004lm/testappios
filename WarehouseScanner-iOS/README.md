# Kho Scanner (iOS) – kết nối với web Warehouse Tina

App Swift/SwiftUI (iOS 16+) dùng camera iPhone **thay máy quét barcode**. Phiên nhận hàng được tạo trên web; app chỉ chọn phiên đang mở rồi quét.

**Quét tự động 1 lần:** camera chạy liên tục, mỗi nhãn được đọc đồng thời **barcode** (AVFoundation) và **mã kho** (Vision OCR, khớp regex từ `GET /warehouse/rules`) rồi tự gửi lên web (`POST /receiving/sessions/:id/scan`) — không hỏi xác nhận. Nhãn không đọc được mã kho/barcode trong ~3,5 giây sẽ bị **bỏ qua** (đếm ở ô BỎ QUA). Mất mạng thì tự gửi lại mỗi 4 giây. App chỉ hiển thị nhãn thuộc **kho nào**, không phân loại kinh doanh. Nút **Báo hỏng** (tuỳ chọn) chụp ảnh gắn vào kiện vừa quét.

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
| `InboundViewModel.swift` | Module 1: gửi nền, chống đọc lặp, báo hỏng |
| `ClassifyViewModel.swift` | Module 2: ghép mã vạch + mã kho trong cửa sổ 4 giây |
| `RuleMatcher.swift` | Khớp regex như server + sửa lỗi OCR (`_` bị mất, `0`/`O`) |
| `APIClient.swift` | Gọi API web |
