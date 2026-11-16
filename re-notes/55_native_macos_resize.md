# Zalolite: phân tích video và vòng đời bố trí transcript

Ngày kiểm tra: 2026-11-11. Video riêng tư được giải mã cục bộ, không đưa ảnh
hoặc nội dung hội thoại vào repository hay dịch vụ bên ngoài.

## Bằng chứng và giới hạn

- Video dài 33,55 giây, 1852 × 1216. Các khung ở mốc 7,5 và 13,5 giây cho
  thấy vùng hội thoại bị thu thành một dải trắng cao; từ khoảng giây 14 nội
  dung xuất hiện trở lại. Đây là lỗi hiển thị thực tế, không phải thời gian
  truy vấn SQLite được suy ra từ ảnh.
- Telegram nằm phía sau Zalolite trong video. Không coi clip này là phép đo
  FPS hay phép so sánh trực tiếp thao tác kéo viền hai cửa sổ.
- Telegram đã cài trên máy có bundle ID `ru.keepcoder.Telegram`, phiên bản
  13.1.0. Đây là Telegram macOS native. Tham khảo Telegram Desktop dùng Qt
  trước đó chưa mô tả đúng ứng dụng này.

## Đối chiếu mã nguồn công khai

Nguồn chính thức: [Telegram macOS](https://github.com/TelegramMessenger/telegram-macos),
commit tham khảo `ec221d8560ca693cb921b4e8c576da9b87dff9ef`.
Không khẳng định commit này trùng chính xác mã của binary 13.1.0 đã cài.

- [TableView.swift](https://github.com/TelegramMessenger/telegram-macos/blob/ec221d8560ca693cb921b4e8c576da9b87dff9ef/packages/TGUIKit/Sources/TableView.swift#L4647):
  khi đổi chiều rộng, `setFrameSize` gọi `layoutIfNeeded` với `visibleRows()`.
  Khi kết thúc live resize, `viewDidEndLiveResize` mới gọi `layoutItems`.
- [ChatController.swift](https://github.com/TelegramMessenger/telegram-macos/blob/ec221d8560ca693cb921b4e8c576da9b87dff9ef/packages/ChatUI/Sources/ChatUI/ChatController.swift#L2030):
  lượt đầu có thể chuẩn bị đủ vùng nhìn thấy trên main queue; phần còn lại
  có đường chuẩn bị trên message queue. Không phải mọi phép bố trí đều chạy
  ngoài main thread.
- [TextViewPreparedText.swift](https://github.com/TelegramMessenger/telegram-macos/blob/ec221d8560ca693cb921b4e8c576da9b87dff9ef/packages/TGUIKit/Sources/TextViewPreparedText.swift):
  tái sử dụng attributed text bất biến và CoreText typesetter. Zalolite vẫn
  dùng SwiftUI hosting cho nội dung hàng, nên còn khác biệt về chi phí mỗi hàng.

## Điểm nghẽn xác nhận trong Zalolite

Trước thay đổi, mỗi chiều rộng mới làm `prepareHeights` đo lại toàn bộ vùng
đã tải bằng `NSHostingController.sizeThatFits` trên main actor rồi reload
bảng. Lưu tin xuống SQLite không loại bỏ được công việc bố trí này.

Đo release trên MacBookPro18,3, Apple M1 Pro 10 nhân, RAM 32 GB, macOS 27.0.
Dữ liệu giả lập gồm văn bản và trích dẫn, không mạng, không tài khoản thật.
Mỗi tập có sáu lần đổi chiều rộng; số P95 trong phép đo nhỏ này là mẫu lớn
nhất, không phải percentile đại diện cho sử dụng thực tế.

| Số tin đã tải | Trung bình trước thay đổi |
| ---: | ---: |
| 20 | 56,67 ms |
| 50 | 102,38 ms |
| 200 | 343,78 ms |
| 400 | 665,00 ms |

Log gốc: `output/performance-diagnostics-20261111/resize-component-before.log`.
Đây là thời gian cập nhật component, không phải FPS, độ trễ bấm đến khi
hiện ảnh, hay benchmark Telegram.

## Thay đổi đang kiểm chứng

Giữ SQLite/Rust, SwiftUI message content và các tương tác hiện có. Chuẩn bị
chiều cao chính xác cho vùng đọc trước; các hàng ngoài màn hình dùng chiều
cao đã biết làm ước lượng. Sửa chiều cao theo message ID và độ lệch trong
hàng để giữ nguyên vị trí đọc. Không reload toàn bộ bảng khi chỉ đổi chiều
rộng; cấu hình lại các cell đang có.

Chuẩn bị phần ngoài màn hình theo lượt tối đa ba hàng hoặc khoảng 3 ms
đo layout, nhường main queue giữa các lượt. Ngân sách này không bao gồm
toàn bộ chi phí áp dụng layout, không phải cam kết thời gian khung hình.
Hủy lượt cũ khi đổi thread/chiều rộng/nội dung, tạm dừng khi live scroll
hoặc live resize. SwiftUI hosting vẫn phải được đo trên main actor.

Các kiểm tra bắt buộc: vùng nhìn thấy có chiều cao chính xác, không đo
toàn bộ 400 tin trong lượt tương tác; giữ anchor sau cuộn/co giãn/thêm tin
cũ; đổi thread phục hồi vị trí riêng; kiểm tra ảnh và clipping trên app.

Nếu chi phí các cell đang nhìn thấy vẫn cao, bước tiếp theo là prototype
render item AppKit/CoreText cho nội dung tin. Không coi việc chuyển sang
NSTableView hoặc một bộ unit test đạt là bằng chứng đã mượt như Telegram.

## Trạng thái bàn giao lúc 21:26 +07

46 kiểm thử Swift đạt sau thay đổi tái dùng hosting cell. Benchmark 400 tin:
trung bình 10,14 ms, mẫu lớn nhất 13,58 ms (sáu lần đổi chiều rộng). Người
dùng xác nhận màn hình 120 Hz và yêu cầu giao phần còn lại cho Claude Code
tự chọn giải pháp. Ngân sách một khung là khoảng 8,3 ms; phép đo component
hiện tại chưa đạt bằng chứng chạy mượt 120 FPS. Chưa đóng gói hoặc thay app
đang chạy. Chi tiết ngắn ở `output/performance-diagnostics-20261111/handoff-claude-code-120hz.md`.
