# SteamFix — Steam Network Diagnostics & Repair Tool

**SteamFix** là công cụ dành cho Windows, viết dưới dạng một file `.bat` tích hợp PowerShell và C#, nhằm kiểm tra, chẩn đoán và thử khắc phục một số lỗi kết nối Steam có thể liên quan đến DNS, phân giải tên miền hoặc việc lọc kết nối TLS/SNI trên đường truyền.

Công cụ hướng đến các tình huống như:

- Steam Store hoặc Community không tải giao diện, CSS bị thiếu hoặc trang trắng.
- Steam báo lỗi kết nối như **`-105`**.
- Avatar người chơi trong Steam/CS2 hiển thị ảnh mặc định.
- Một số tên miền Steam hoặc máy chủ phân phối nội dung tải game không thể kết nối.

> **Lưu ý:** Đây là công cụ chẩn đoán và sửa lỗi theo từng trường hợp, không phải giải pháp bảo đảm khắc phục mọi lỗi Steam. Kết quả còn phụ thuộc vào nhà mạng, DNS, tuyến mạng, trạng thái máy chủ Steam và cấu hình Windows.

## Tính năng chính

### 1. Kiểm tra và chẩn đoán kết nối Steam

- Kiểm tra phân giải DNS và kết nối HTTPS đến danh sách tên miền Steam được cấu hình trong công cụ.
- Phân biệt một số tình huống như không phân giải được DNS, kết nối TCP thất bại hoặc kết nối TLS/HTTPS gặp lỗi.
- Đối chiếu DNS của Windows với truy vấn DNS-over-HTTPS khi cần.
- Hiển thị trạng thái và kết quả theo từng tên miền để người dùng có thêm dữ liệu xác định nguyên nhân.

### 2. Local TCP relay thử nghiệm cho kết nối TLS/SNI

SteamFix có thể thử chạy một relay TCP cục bộ tại `127.0.0.1`, sau đó kiểm tra nhiều cách gửi phần mở đầu TLS (**ClientHello**) với cách chia dữ liệu khác nhau.

Nếu một tên miền vượt qua bước kiểm tra, công cụ có thể đề xuất chuyển hướng tên miền đó qua relay bằng một khối riêng trong file `hosts`. Relay được thiết kế để chuyển tiếp dữ liệu TLS, không giải mã nội dung HTTPS.

Cơ chế này chỉ có thể hữu ích với một số kiểu lọc kết nối nhất định. Nó **không bảo đảm vượt được mọi hình thức chặn**, chẳng hạn trường hợp đường truyền chặn theo địa chỉ IP hoặc chính kết nối đến máy chủ đích bị lỗi.

### 3. Quản lý DNS

- Đặt DNS IPv4/IPv6 sang Google DNS và Cloudflare DNS.
- Thử cấu hình DNS-over-HTTPS (DoH) nếu phiên bản Windows hỗ trợ các lệnh cần thiết.
- Hiển thị DNS hiện tại để người dùng kiểm tra.
- Có lựa chọn đặt lại DNS của adapter về chế độ tự động.

### 4. Quản lý file `hosts` có sao lưu

- Chỉ thêm các tên miền đã vượt qua bước kiểm tra relay.
- Đặt các dòng do SteamFix quản lý trong một khối có dấu bắt đầu/kết thúc riêng.
- Tạo bản sao lưu trước khi ghi file và kiểm tra lại nội dung sau khi ghi.
- Giữ nguyên các dòng khác ngoài phần công cụ quản lý khi thêm hoặc gỡ khối SteamFix.
- Phát hiện một số dấu hiệu file `hosts` bị lỗi định dạng và hỗ trợ khôi phục từ bản sao lưu phù hợp khi tìm thấy.

Nếu phát hiện các dòng `hosts` đang chuyển hướng tên miền Steam nhưng không thuộc khối SteamFix, công cụ có thể hỏi trước khi vô hiệu hóa chúng. Hãy đọc kỹ nội dung hiển thị trước khi đồng ý.

### 5. Dọn cache và khởi động lại Steam

Có thể xóa các cache liên quan đến trình duyệt Steam và avatar để Steam tải lại giao diện hoặc hình ảnh. Công cụ sẽ hỏi trước khi đóng Steam đang chạy.

### 6. Chẩn đoán chuyên biệt

- **SNI/IP:** thử phân biệt dấu hiệu kết nối bị reset theo tên miền TLS hay theo nhóm địa chỉ IP.
- **Tải game:** đọc một phần `content_log.txt` và kiểm tra các tên miền phân phối nội dung Steam.
- **Avatar:** kiểm tra log relay, avatar cache, thử tải avatar và xem các kết nối TCP của Steam/SteamWebHelper/CS2.
- **Relay log:** xem các dòng log gần nhất để biết relay có nhận kết nối hay gặp lỗi.
- **QUIC:** tùy chọn thêm hoặc gỡ quy tắc Windows Firewall chặn UDP cổng 443 cho `steamwebhelper.exe`, nhằm thử buộc trình duyệt Steam dùng TCP khi gặp vấn đề tương thích. Đây không phải lựa chọn cần bật mặc định.

## Cách sử dụng

1. Tải `STEAM FIX.bat` từ repository về máy Windows.
2. Kiểm tra mã nguồn trước khi chạy, đặc biệt vì công cụ cần quyền Administrator để thực hiện một số tác vụ hệ thống.
3. Chạy file và chấp thuận yêu cầu quyền quản trị nếu muốn tiếp tục.
4. Đọc phần kiểm tra trạng thái xuất hiện lúc khởi động, sau đó chọn chức năng trong menu.
5. Nếu muốn thử phương án tổng thể, chọn **`[1] SUA TOAN DIEN`**. Công cụ sẽ kiểm tra các tên miền, thử cài relay và yêu cầu xác nhận trước khi ghi các ánh xạ relay vào `hosts`.
6. Nếu cần tìm nguyên nhân thay vì thay đổi cấu hình, ưu tiên các mục chẩn đoán như **`[2]`**, **`[3]`**, **`[11]`**, **`[12]`** hoặc **`[13]`**.

### Menu chức năng

| Mục | Chức năng |
|---|---|
| `[1]` | Sửa tổng thể: DNS, DoH nếu hỗ trợ, kiểm tra/cài relay, kiểm tra kết nối và khởi động lại Steam |
| `[2]` | Quét lại kết nối và xem trạng thái DNS/relay |
| `[3]` | Thử nghiệm các cách chia TLS ClientHello |
| `[4]` | Gỡ relay và khối `hosts` do SteamFix quản lý |
| `[5]` | Dọn cache web/HTTP/avatar của Steam và khởi động lại |
| `[6]` | Chỉ đặt DNS Google/Cloudflare và thử bật DoH |
| `[7]` | Đặt DNS adapter về chế độ tự động |
| `[8]` / `[9]` | Bật / gỡ quy tắc chặn QUIC cho SteamWebHelper |
| `[10]` | Xem log relay |
| `[11]` | Chẩn đoán dấu hiệu lọc theo SNI hay IP |
| `[12]` | Chẩn đoán kết nối máy chủ tải game |
| `[13]` | Chẩn đoán avatar và đường kết nối CDN |
| `[0]` | Thoát |

## Yêu cầu và cách hoạt động

- Windows với Windows PowerShell và các thành phần mạng/lập lịch tác vụ được công cụ sử dụng.
- Quyền **Administrator** cho các thao tác thay đổi DNS, `hosts`, firewall hoặc Scheduled Task.
- Kết nối Internet để kiểm tra các dịch vụ DNS công cộng và máy chủ Steam.
- Không yêu cầu cài Python hoặc tải riêng một thư viện relay: phần C# được biên dịch tại chỗ bằng cơ chế .NET `Add-Type` của PowerShell.
- Hỗ trợ DoH phụ thuộc phiên bản Windows và các lệnh quản lý DNS có sẵn trên hệ thống.

## Những thay đổi hệ thống cần biết

Trước khi chạy, hãy lưu ý SteamFix có thể thực hiện các thao tác sau tùy mục được chọn:

- Thay đổi DNS của các adapter mạng đang được công cụ chọn xử lý; cấu hình DoH có thể được đăng ký trong Windows.
- Tạo Scheduled Task tên **`SteamFix Relay`**, chạy relay bằng tài khoản hệ thống khi khởi động hoặc đăng nhập.
- Lắng nghe cổng TCP cục bộ `127.0.0.1:443` và, khi bật phần HTTP, `127.0.0.1:80`.
- Ghi khối ánh xạ tên miền Steam vào file `hosts`, sau khi người dùng xác nhận.
- Xóa cache web/HTTP/avatar của Steam khi chọn chức năng dọn cache.
- Thêm quy tắc Windows Firewall nếu người dùng bật tùy chọn chặn QUIC.

**Gỡ relay không đồng nghĩa mọi cấu hình đều tự quay về trạng thái trước đó.** Mục `[4]` gỡ relay và khối `hosts` do công cụ quản lý; nếu đã bật chặn QUIC thì dùng `[9]` để gỡ quy tắc đó. Mục `[7]` đặt DNS adapter về tự động, không khôi phục chính xác DNS tĩnh tùy chỉnh trước đây. Hãy ghi lại cấu hình mạng ban đầu nếu máy đang dùng DNS hoặc thiết lập đặc biệt.

## Giới hạn

- SteamFix không sửa lỗi máy chủ Steam, lỗi tài khoản, lỗi game hoặc lỗi cài đặt ứng dụng.
- Việc đổi DNS không tự giải quyết được mọi vấn đề TLS/SNI hoặc chặn theo IP.
- Relay chỉ áp dụng cho các tên miền được kiểm tra và cấu hình; các kết nối Steam khác có thể không đi qua relay.
- Kết quả chẩn đoán là dấu hiệu kỹ thuật để khoanh vùng nguyên nhân, không phải bằng chứng tuyệt đối về chính sách của nhà mạng.
- Nếu relay không thể kết nối tới máy chủ đích, hoặc kiểu lọc mạng không phù hợp với cơ chế chia TLS, công cụ có thể không khắc phục được lỗi.

## Nhật ký

Dữ liệu và log của relay được lưu trong:

```text
%ProgramData%\SteamFix\
```

Trong đó có thể có `relay.log`, `relay-error.log` và dữ liệu hỗ trợ relay. Các log hữu ích khi gửi báo lỗi; hãy kiểm tra và che thông tin cá nhân hoặc dữ liệu nhạy cảm trước khi công khai.

## Đóng góp và báo lỗi

Khi báo lỗi, vui lòng mô tả phiên bản Windows, nhà mạng hoặc loại kết nối đang dùng, triệu chứng gặp phải và mục menu đã chạy. Nếu đính kèm log, chỉ chia sẻ phần cần thiết và xóa thông tin riêng tư trước khi đăng.

## Tuyên bố miễn trừ trách nhiệm

Công cụ được cung cấp cho mục đích chẩn đoán và khắc phục sự cố kết nối trên máy của người dùng. Hãy đọc mã nguồn trước khi chạy và tự đánh giá các thay đổi hệ thống mà công cụ đề xuất. Tác giả không bảo đảm công cụ sẽ hoạt động trên mọi cấu hình mạng hoặc chịu trách nhiệm cho các thay đổi do người dùng chủ động xác nhận.

---

**Author:** TimmyHeart - V — Tran Hieu Nghia
