# Zalolite 120 Hz — tiếp quản phần Claude Code làm dở

Ngày: 2026-11-11. Mục tiêu màn hình 120 Hz tương ứng khoảng 8,33 ms mỗi khung.

## Đã kiểm tra từ phiên Claude và mã nguồn

Claude đã thêm renderer AppKit/CoreText cho văn bản, trích dẫn, liên kết,
reaction và ảnh; sticker động và thẻ tệp vẫn dùng SwiftUI. Có cache typesetter,
layout, vùng layer nhỏ và công cụ đo bằng CADisplayLink với dữ liệu giả lập.
Claude cũng thêm `CursorThrift` sau khi lấy mẫu thấy nhiều thời gian nằm
trong nhánh AppKit đặt lại ảnh con trỏ. Phiên dừng khi một bài kiểm thử mới
có hai assertion không đạt; còn các bài khác đạt hoặc được bỏ qua có chủ ý.

Các tệp đang có được giữ nguyên làm điểm tiếp quản; không reset Git hoặc
ghi đè bằng bản sao cũ. Bản sao nguồn trước Claude nằm trong thư mục chẩn
đoán, còn checkpoint trước đợt tiếp quản này nằm ở `/private/tmp`.

## Hoàn thiện bởi Codex

- Sửa fixture kiểm tra bong bóng không có nhãn ngày; thêm ca riêng chứng
  minh nhãn ngày ở giữa phải được vẽ lại khi đổi chiều rộng.
- Sửa chữ ký vẽ lại: một nhãn ngày/avatar không tồn tại phải có giá trị cố
  định, thay vì phụ thuộc vị trí tuyệt đối của bong bóng gửi đi.
- Giới hạn ảnh theo phần nội dung thật của bong bóng sau khi trừ avatar,
  checkbox và khoảng cách bên đối diện; thêm kiểm tra chiều rộng 240–640 pt,
  cả chiều gửi/nhận và có/không có chú thích.
- Làm mới ảnh đại diện đã cache khi URL thay đổi, dù tên và nội dung tin
  giữ nguyên. Lệnh đổi con trỏ khác loại vẫn đi qua ngay; ngoài main thread
  dùng hàm AppKit gốc thay vì assert actor isolation.
- Bổ sung trạng thái cửa sổ hiển thị trong probe, cho cửa sổ chẩn đoán xuất
  hiện trên desktop toàn màn hình; kịch bản không chọn hội thoại không bị
  đếm nhầm là một hàng lỗi.

Kiểm thử release: **54 bài, 0 lỗi, 1 benchmark tùy chọn được bỏ qua**.
Log: `output/performance-diagnostics-20261111/codex-resume-swift-tests.log`.
Lệnh dùng SwiftPM `--build-system native` vì bộ dựng mặc định của Xcode bị
kẹt ở cache SDK trong môi trường hiện tại.

## Bằng chứng hiệu năng và giới hạn

Máy M1 Pro, 32 GB, macOS 27.0; nguồn dữ liệu giả lập, ảnh được giải mã sẵn,
không dùng tài khoản thật. Báo cáo của Claude đã được giữ nguyên:
`frame-probe-before.json` và `frame-probe-after.json` dưới thư mục chẩn đoán.

Lượt `frame-probe-resumed.json` cho thời gian chuyển lại hội thoại trung bình
khoảng 40 ms; không có hàng sai kích thước khi dừng, giữ anchor khi co giãn.
Vẫn có rớt callback và một lần lệch khoảng 13 pt khi cuộn 15.000 pt/giây.
Tuy nhiên cờ hiển thị cuối lượt là false, nên không dùng lượt này để tuyên bố
FPS trên màn hình hoặc tính mức tăng so với lượt khác điều kiện cửa sổ.

Phép kéo cửa sổ trong probe gọi `NSWindow.setFrame(..., display:true)` đồng
bộ trên mỗi callback. Nó bao gồm cả chi phí shell/WindowServer; thời gian
cập nhật transcript thấp không đồng nghĩa toàn cửa sổ đạt 120 FPS. Không
coi trạng thái build/test đạt là chấp nhận thị giác hoặc tốc độ hoàn chỉnh.

Ảnh fixture kiểm tra bố cục ở
`output/performance-diagnostics-20261111/resume-probe-shots/` chỉ chứa dữ liệu
giả lập. Video và ảnh hội thoại thật của người dùng không được sao chép vào
repository hoặc gửi đi.

## Kết quả cuối lượt tiếp quản

- Tách chia cột workspace sang SwiftUI `Layout`; không dùng kích thước từ
  `GeometryReader` để dựng lại toàn bộ workspace trên từng bước kéo cửa sổ.
  Bộ kiểm thử vẫn có 54 bài, 0 lỗi, 1 benchmark tùy chọn bỏ qua; log cuối là
  `resume-workspace-layout-tests.log`.
- So sánh cùng dữ liệu 150 hàng, cửa sổ hiện thật trên màn hình 120 Hz,
  `resize_mid_history_1200pt_s`: P95 của lượt main-run-loop từ 26,59 xuống
  16,58 ms; callback bị lỡ từ 321 xuống 202. Ở cuối cả hai lượt không có
  hàng sai kích thước và độ lệch anchor bằng 0. Đây là hai lượt kiểm tra
  phát hiện cải thiện, không phải phân bố thống kê dài hạn hay bằng chứng
  đã đạt 120 FPS. Nguồn: `frame-probe-visible-resize.json` và
  `frame-probe-workspace-layout.json` trong thư mục chẩn đoán.
- **Co giãn nhanh vẫn còn vượt ngân sách 8,33 ms/khung.** Lấy mẫu CPU còn
  thấy chi phí layout của SwiftUI shell và cập nhật structural/tracking
  regions của AppKit. Dữ liệu trong `resume-resize-cpu-sample.txt` được lấy
  khi chạy profiler, không dùng như một lượt đo FPS độc lập.
- Đã đóng gói và kiểm tra chữ ký `dist/Zalolite.app`, build
  `20261111155938`. Các section `__TEXT` của frontend và worker trong bundle
  khớp binary tương ứng (hash toàn file khác sau khi ký là bình thường).
- Đã mở bản mới, chuyển hai hội thoại, cuộn lên, zoom/khôi phục cửa sổ và
  kiểm tra ảnh/văn bản hiển thị. Trong những trạng thái quan sát không thấy
  dải trắng, nội dung đè header/composer hoặc ảnh tràn ngang. CUA không hỗ
  trợ kéo tọa độ ở phiên này; thao tác zoom được kiểm qua Accessibility,
  còn kéo liên tục được đo bằng probe. Không coi đây là kiểm thử hết mọi
  chức năng hoặc xác nhận thị giác từ người dùng.
- Đã tắt `Auto-continue when limits reset` của đúng phiên Claude đang dở
  để tránh tự sửa chồng sau khi được cấp lại quota. Không gửi thêm prompt
  hoặc thay đổi gói sử dụng Claude. Nguồn clone gốc được giữ nguyên.
