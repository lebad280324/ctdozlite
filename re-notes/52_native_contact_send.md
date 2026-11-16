# Gửi danh thiếp từ Native (11/11/2026)

Nguồn: mã ứng dụng Zalo PC đang cài tại `/Applications/Zalo.app/Contents/Resources/app.asar`,
bundle `compact-app-pc.cfeba43a9a8e4e40dda3.js`, hàm `forwardContactOA`.

- Cá nhân: service CHAT, `POST /api/message/contact`, command ID 11774.
  Tham số: `toId`, `clientId`, `contactId`; lưu ý chữ I hoa trong `toId`.
- Nhóm: service GROUP, `POST /api/group/contact`, command ID 11827.
  Tham số: `grid` bỏ tiền tố hội thoại, `visibility`, `clientId`, `contactId`.
- PC chọn `gContactId` cho trường hợp khác; Native chỉ cung cấp liên hệ UID
  trong danh sách liên hệ. Các trường QR/oaShortLink của PC là tùy chọn.
- Native sử dụng `session.encoded_params`, `post_endpoint_form`, cookie và
  kiểm tra acknowledgement của đường dẫn chuẩn hiện có. Client ID tạo một lần;
  không tự retry gửi. Chỉ hiển thị thành công sau khi server chấp nhận.

Kiểm thử fixture: khóa người nhận phân biệt hoa thường, prefix nhóm, client ID.
Chưa gửi danh thiếp bằng tài khoản thật trong đợt này để tránh gửi dữ liệu ngoài ý muốn.
Chưa xác định API sửa nội dung tin đã gửi: không quảng bá capability sửa tin.
Định dạng chữ sử dụng bộ chuyển Markdown → textProperties hiện có trong `chat.rs`.
