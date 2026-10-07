# Warehouse Receiving System (TinaShipping - OR_1 Hub Oregon)

Node.js/Express + PostgreSQL + Vue 3 / Tailwind.

```
server/   API Express (config/, controllers/, routes/, utils/, schema.sql, index.js)
client/   Vue 3 SPA (src/views/SessionList.vue, SessionScan.vue)
```

## Chạy thử

1. Tạo database và cấu hình:
   ```bash
   createdb warehouse
   cd server
   cp .env.example .env      # sửa DATABASE_URL cho đúng máy bạn
   npm install
   npm run db:init           # chạy schema.sql (chạy lại nhiều lần vẫn an toàn)
   npm run dev               # API: http://localhost:3000
   ```
2. Frontend (terminal khác):
   ```bash
   cd client
   npm install
   npm run dev               # http://localhost:5173 (tự proxy /api -> :3000)
   ```

## API (prefix `/api/v1`)

| Method | Đường dẫn | Mô tả |
|---|---|---|
| GET | `/warehouse/rules` | Quy tắc regex đang bật (dùng cho Web và iOS) |
| GET | `/receiving/sessions?page&limit&status&carrier&date` | Danh sách phiên, phân trang + lọc |
| POST | `/receiving/sessions` | Tạo phiên (`carrier_name` bắt buộc) |
| GET | `/receiving/sessions/:id` | Phiên + kiện đã quét + đếm ngoại lệ |
| POST | `/receiving/sessions/:id/scan` | `{barcode, detected_text}` → khớp regex, lưu kiện. Trùng mã → **409 DUPLICATE_BARCODE** |
| PATCH | `/receiving/sessions/:id/finalize` | "Chốt kiện": đặt tổng kiện = số đã quét |
| PATCH | `/receiving/sessions/:id/close` | Kết thúc phiên |
| PATCH | `/scanned-items/:id/toggle-business-type` | Đổi KINH_DOANH ⇄ KHONG_KINH_DOANH |
| PATCH | `/scanned-items/:id/exception` | `{exception_status}` đánh dấu hư hỏng/giữ hàng/chặn |

Quy tắc khớp: duyệt rule đang bật theo `id` tăng dần, rule đầu tiên khớp (không phân biệt hoa/thường) thắng. Không khớp rule nào → kiện được lưu với `exception_status = UNKNOWN`.
