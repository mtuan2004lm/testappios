# Quy tắc làm việc trong dự án này

- **Mỗi khi sửa bất kỳ thứ gì trong code** (server, web, app iOS, database, cấu hình), phải thêm một mục mới vào `CHANGELOG.md` (phần "Lịch sử", mục mới nhất ở trên cùng): ghi ngày, đã đổi gì, ở file nào, và đánh dấu ⭐ quan trọng / 🔥 khó / 🧪 test / 📱 cần build lại app / 🗄️ cần chạy `npm run db:init`.
- **Cũng cập nhật `README.md`** (mục liên quan + dòng cuối phần "Lịch sử cập nhật"), và `../WarehouseScanner-iOS/README.md` nếu đổi app iPhone. Ba nơi cần đồng bộ: `CHANGELOG.md`, `README.md`, `CLAUDE.md` (khi quy tắc làm việc đổi).
- Nếu thay đổi làm đổi cách hệ thống hoạt động, cập nhật luôn mục 2 ("Những điểm khó / quan trọng") và mục 3 ("Việc chưa làm") trong `CHANGELOG.md`.
- Người dùng giao tiếp bằng tiếng Việt: trả lời tiếng Việt, ngắn gọn.
- Trước khi đưa code về máy người dùng, phải test trong sandbox và hỏi xác nhận.
