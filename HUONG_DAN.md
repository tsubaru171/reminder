# RemindBoard v7 — Hướng dẫn chạy

## Yêu cầu
- Node.js v18+ → https://nodejs.org (tải LTS)

---

## BƯỚC 1 — Tạo Supabase project (miễn phí)

1. Vào https://supabase.com → Sign up (free)
2. Click **New project** → đặt tên → chọn region **Southeast Asia (Singapore)** → Create
3. Chờ ~2 phút

---

## BƯỚC 2 — Tắt email confirmation (để dễ test)

Supabase dashboard → **Authentication** → **Settings** → tắt **"Enable email confirmations"** → Save

---

## BƯỚC 3 — Chạy SQL schema

1. Supabase dashboard → **SQL Editor** → **New query**
2. Copy toàn bộ nội dung file `schema.sql`
3. Paste vào → Click **Run**
4. Thấy "Success" là xong

---

## BƯỚC 4 — Lấy API keys

Supabase dashboard → **Settings** (bánh răng) → **API**

Copy 2 thứ:
- **Project URL**: `https://xxxxxx.supabase.co`
- **anon public key**: `eyJhbGci...`

---

## BƯỚC 5 — Cài và chạy app

Mở Terminal/Command Prompt trong thư mục này:

```bash
npm install
npm start
```

Lần đầu `npm install` mất ~2 phút. Sau đó app tự mở.

---

## BƯỚC 6 — Setup trong app

1. Nhập **Project URL** và **Anon Key** vào màn hình đầu → Connect
2. Đăng ký tài khoản (email + password bất kỳ)
3. Tạo workspace → đặt tên team
4. Copy invite code → gửi cho teammates
5. Teammates: mở app → nhập invite code → join

---

## Build installer cho team

```bash
npm run build:win    # Windows → dist/RemindBoard Setup.exe
npm run build:mac    # Mac     → dist/RemindBoard.dmg
npm run build:linux  # Linux   → dist/RemindBoard.AppImage
```

Gửi file installer cho từng người trong team, ai cũng cài như app bình thường.

---

## Cách app hoạt động

```
Bạn tạo reminder → lưu Supabase
         ↓
Supabase realtime broadcast
         ↓
App của teammate nhận ngay (<1 giây)
         ↓
Fullscreen alert + âm thanh đúng giờ
```
