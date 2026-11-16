# Phạm vi chức năng native theo phân tích BA

Bản phát triển ngày 10/11/2026 giữ phong cách Liquid Glass riêng. “Đã triển khai”
nghĩa là có xử lý và đường gọi thật; không đồng nghĩa đã kiểm chứng với tài khoản
Zalo thật. Trạng thái thử nghiệm nằm trong `output/native-ba-20261110/verification.json`.

| Nhóm | Phần đã triển khai / nối vào app | Phần cần hoàn thiện hoặc xác minh |
| --- | --- | --- |
| Hội thoại | Phân loại và ưu tiên trên máy, đánh dấu chưa đọc, ghim hội thoại, ẩn/xóa, đổi tên gợi nhớ server | Ẩn bằng PIN Zalo; tự xóa, chống chia sẻ, báo xấu chưa đủ hợp đồng giao thức |
| Tin nhắn | Trả lời, chuyển tiếp, cảm xúc, thu hồi/xóa, chi tiết, chọn nhiều và sao chép, lưu ảnh/tệp | Hành động thu hồi/xóa cần xác minh quyền và điều kiện server thực tế |
| Nội dung lưu | Đánh dấu, ghim trên máy, nhắc hẹn, mẫu tin, kho ảnh/tệp/link trong dữ liệu đã tải | Ghim tin nhắn trên server mới có đọc danh sách; không giả ghim toàn nhóm |
| Danh bạ | Bạn bè/nhóm, tìm kiếm/sắp xếp, tìm điện thoại, lời mời, chặn/bỏ chặn, tạo nhóm/thêm thành viên | Danh sách lời mời đang lấy trang đầu và báo partial; cần bổ sung phân trang đầy đủ |
| Bảo mật | Khóa không gian bằng xác thực macOS, khóa khi về nền, đọc/thay đổi 2FA có xác nhận | Luồng OTP cần thử trực tiếp; không lưu OTP và không tự bật/tắt khi mở màn hình |
| Quyền riêng tư | Đọc/cập nhật các khóa server đã quan sát; bộ chặn trạng thái riêng trên thiết bị | Mọi thay đổi server cần đọc lại xác nhận; trường thiếu không được suy diễn |
| Đồng bộ | Đồng bộ điện thoại có tiến độ/hủy; import backup vào DB theo tài khoản | Chưa xác nhận chuyển đủ toàn bộ lịch sử điện thoại trong phiên sử dụng thực |
| Sao lưu và dung lượng | Xuất SQLite không ghi đè, nhập bản sao, tính dung lượng, dọn cache riêng, tải/hủy tệp | Không coi bản xuất cục bộ là bản sao tương thích khôi phục trên điện thoại |
| Cuộc gọi | Gọi/nhận/kết thúc, mic/camera, khung video, chọn thiết bị qua engine Rust hiện có | Chưa kiểm chứng cuộc gọi thật; video còn cần ffmpeg và quyền thiết bị |
| macOS | Thông báo/nhắc hẹn, quyền hệ thống, mở cùng máy, phím tắt chụp khi app có focus | Chưa có phím tắt toàn hệ thống, đa ngôn ngữ, Excel thành ảnh, tìm GIF/prefetch tự động |

Ghim/đánh dấu/phân loại trên máy có phạm vi tài khoản trong SQLite. Dữ liệu không
được dùng chung giữa các tài khoản. Giao diện không dùng nút bật/tắt giả cho các
chức năng chưa có xử lý. Thiết lập thông báo của ứng dụng không vượt quyền macOS.

Nguồn hợp đồng mới: `re-notes/47_native_ba_settings.md` và
`re-notes/48_native_ba_actions.md`. Các kiểm thử chỉ dùng fixture/dữ liệu mẫu,
không tự gọi, gửi tin hoặc thay đổi bảo mật của tài khoản thật.

## Bổ sung đợt 2 (10/11/2026, giao diện SwiftUI)

Đợt này không thay đổi giao thức hay lõi Rust; chỉ nối các lệnh đã có vào giao diện
và thêm tích hợp macOS. Chưa có mục nào được thử với tài khoản Zalo thật.

| Mã BA | Phần bổ sung | Giới hạn cần biết |
| --- | --- | --- |
| CHAT-01 | Thanh Ưu tiên/Khác (bật tắt trong Cài đặt > Tin nhắn), nhãn phân loại, chỉ báo “Nháp”, trạng thái đang tải / không có kết quả / bộ lọc trống / mất kết nối | Ưu tiên và phân loại vẫn lưu trên máy |
| CHAT-02, luồng 4 | Nhảy tới tin gốc từ trích dẫn trả lời, mục đã lưu, ghim trên máy, thư viện và kết quả tìm kiếm | Chỉ tìm trong tối đa 2.000 tin đã tải của hội thoại; ngoài phạm vi đó báo lỗi rõ |
| CHAT-03, luồng 1 | Tìm trong lịch sử đã lưu (⇧⌘F), giới hạn theo hội thoại đang mở; ⌘F tìm trong hội thoại | Tìm trên SQLite cục bộ, tối đa 300 kết quả; không tìm trên máy chủ |
| CHAT-04 | Gợi ý mẫu tin khi gõ `/`, gợi ý tên thành viên khi gõ `@`, gợi ý nhãn dán theo từ đang gõ; chọn nhiều tệp, kéo thả và dán tệp/ảnh; tệp chờ trong ô soạn đến khi nhấn Gửi | `@` chèn tên dạng văn bản, chưa tạo thông báo nhắc tên (lõi gửi `mentionInfo` rỗng); gợi ý nhãn dán gửi từ đang gõ tới Zalo |
| CHAT-05, CHAT-06 | Inspector có tên gợi nhớ/phân loại, nhắc hẹn, tạo nhóm, thêm vào nhóm, chặn, ẩn, xóa; danh sách nhắc hẹn và ghim của hội thoại; thư viện mở rộng “Xem tất cả” | Thư viện vẫn chỉ gồm nội dung đã tải |
| CHAT-07 | Thanh thao tác khi rê chuột (trả lời, cảm xúc, chuyển tiếp, đánh dấu); chọn nhiều để sao chép, chuyển tiếp, đánh dấu, xóa phía tôi có xác nhận; bỏ ghim trên máy | Chuyển tiếp nhiều tin gửi từng tin một |
| CHAT-08 | Thêm vào nhóm, tạo nhóm với người này, đánh dấu đã đọc/chưa đọc | Báo xấu vẫn chưa có hợp đồng giao thức |
| CONTACT-01 | Nhóm theo chữ cái (bỏ dấu tiếng Việt), menu từng người (nhắn tin, tên gợi nhớ, tạo nhóm, thêm vào nhóm, chặn có xác nhận), trạng thái tải/trống, thu hồi lời mời đã gửi | Danh sách lời mời/chặn vẫn chỉ có trang đầu |
| APP-01 | Menu tài khoản: thông tin tài khoản, dữ liệu, đồng bộ, ngôn ngữ, hỗ trợ, đăng xuất, thoát | Ngôn ngữ giao diện vẫn chỉ có tiếng Việt |
| Ẩn hội thoại | Tab “Hội thoại ẩn” sau xác thực macOS, cho phép hiện lại | Là lớp bảo vệ trên máy, không phải mã PIN ẩn trò chuyện của Zalo |
| Thông báo | Thông báo tin nhắn mới theo hội thoại, tôn trọng tắt thông báo/ẩn/khóa; tùy chọn xem trước nội dung; huy hiệu Dock; thông báo cuộc gọi đến khi app ở nền; nhấn thông báo mở đúng hội thoại theo ID | Dựa trên số chưa đọc tăng giữa hai lần cập nhật danh sách; cần quyền thông báo của macOS |
| Cài đặt | Tìm theo từng tùy chọn, liên kết thẳng tới trang, chỉ báo đang đọc/đang lưu, thư mục lưu tệp mặc định, dung lượng còn trống, hủy tải | “Ghi nhớ tài khoản” chỉ hiển thị trạng thái; muốn không ghi nhớ thì đăng xuất |
| Tải tệp | Thanh trạng thái tải với Hủy tải và Hiện trong Finder | Mỗi lúc một tệp, theo lõi hiện tại |

Vẫn chưa làm vì thiếu bằng chứng giao thức hoặc nguồn dữ liệu: nhắc tên thật, ghim tin
trên máy chủ, PIN ẩn trò chuyện của Zalo, tự xóa/báo xấu, trạng thái đã nhận/đã xem
từng tin, thẻ lịch sử cuộc gọi, thời hạn tắt thông báo, dán Excel thành ảnh, tìm GIF,
tải trước media, đa ngôn ngữ và phím tắt toàn hệ thống.

## Bổ sung đợt 3 (10–11/11/2026): bố cục kiểu Messages và nhập bản xuất Zalo PC

- **Bố cục:** hai vùng với tay kéo ẩn và trang thông tin toàn bề rộng khi mở. Thanh bên có danh sách
  hội thoại (dòng đang chọn tô màu nhấn, chấm màu cho tin chưa đọc). Dải biểu tượng
  và thanh tài khoản cũ được gom vào nút lọc trên thanh công cụ (xem, lọc, tài khoản,
  cài đặt). Khung trò chuyện dùng bong bóng xám/màu nhấn, mốc giờ ở giữa sau mỗi
  15 phút hoặc ngày mới, ô soạn dạng viên với nút thêm nội dung. Bảng thông tin dùng
  thẻ nhóm. Ảnh kiểm tra với dữ liệu mẫu: `output/native-ba-20261110/demo-*.png`.
- **Giới hạn của bố cục:** giờ từng tin chỉ hiện khi rê chuột; không có trạng thái
  đã gửi/đã xem vì lõi chưa cung cấp. Màn Cài đặt giữ nguyên kiểu biểu mẫu macOS.
- **Nhập `.zl.zip`:** đọc theo luồng, không giới hạn dung lượng, có tiến độ và dừng;
  chi tiết và bằng chứng ở `docs/MACOS_NATIVE.md`, `re-notes/49`–`51`. Media trong
  bản xuất chưa được sao chép. Tệp `.db`/`.sqlite` không còn giới hạn 256 MB; tệp
  `.json` tối đa 2 GB.

Đợt tinh chỉnh 11/11: nền chung ngoài thẻ danh sách; ô soạn có lớp nền dễ đọc,
trả lời và thẻ thumbnail đính kèm nằm bên trong; ảnh chờ gửi không có tên file.
Bổ sung các định dạng clipboard file của Finder/history, chuyển động có Giảm
chuyển động, transcript độc lập với bản nháp và tải ảnh inline có giới hạn/cache.
Chi tiết và giới hạn xác minh ở `docs/MACOS_NATIVE.md`.

Đợt tiếp theo: tìm kiếm trên toolbar theo liên hệ/tin nhắn/tệp; danh sách gọn hơn,
bỏ đường chia, bỏ mask góc bổ sung. Ô soạn cao đều 44 pt và emoji bên trong.
Trang chi tiết rộng có X/Esc. Thao tác tin nhắn chuyển hoàn toàn sang chuột phải.
Bảng thêm nội dung có gửi danh thiếp Zalo, định dạng, nhắc hẹn và chọn đánh dấu
tin quan trọng (hai mục lưu trên máy). Danh thiếp có kiểm thử payload/IPC nhưng
chưa thử gửi thật; sửa tin đã gửi chưa có capability. Nguồn giao thức: re-notes/52.
