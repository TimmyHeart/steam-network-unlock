**Ngôn ngữ:** **Tiếng Việt** | [English](README_EN.md)

# SteamFix — Steam Network Diagnostics & Repair Tool

**Phiên bản hiện tại: v5.2**

**SteamFix** là công cụ dành cho Windows, viết dưới dạng một file `.bat` tích hợp PowerShell và C#, nhằm kiểm tra, chẩn đoán và thử khắc phục một số lỗi kết nối Steam có thể liên quan đến DNS, phân giải tên miền hoặc việc lọc kết nối TLS/SNI trên đường truyền. Từ v5.1, công cụ còn có phần thử khắc phục lỗi **MW4 Texture Streamer** (không tải được texture) trên máy không có IPv6 thực.

Công cụ hướng đến các tình huống như:
- Steam Store hoặc Community không tải giao diện, CSS bị thiếu hoặc trang trắng.
- Steam báo lỗi kết nối như **`-105`**.
- Avatar người chơi trong Steam/CS2 hiển thị ảnh mặc định.
- Một số tên miền Steam hoặc máy chủ phân phối nội dung tải game không thể kết nối.
- MW4 không tải được texture qua Texture Streamer (tên miền CDN `cod-assets.cdn.callofduty.com`), thường gặp khi máy không có địa chỉ IPv6 thực.

> **Lưu ý:** Đây là công cụ chẩn đoán và sửa lỗi theo từng trường hợp, không phải giải pháp bảo đảm khắc phục mọi lỗi Steam hoặc lỗi game. Kết quả còn phụ thuộc vào nhà mạng, DNS, tuyến mạng, trạng thái máy chủ Steam/CDN của game và cấu hình Windows.

## Có gì mới

- **v5.1 — Sửa lỗi MW4 Texture Streamer (IPv6):** thêm mục **`[14]`** (bật) và **`[15]`** (chẩn đoán, chỉ đọc). Relay nghe thêm trên IPv6 loopback `[::1]:443` và `[::1]:80`; file `hosts` được ghi thêm dòng `::1` cho tên miền CDN của game. Relay chấp nhận thêm tên miền dạng `*.cdn.callofduty.com`.
- **v5.2 — Chế độ dự phòng cho MW4:** nếu relay **không mở được `[::1]`**, công cụ không bỏ hẳn phần MW4 mà lùi về chế độ chỉ ghi dòng `127.0.0.1`, kèm cảnh báo rõ ràng rằng chế độ này **chưa chắc chạy**. Công cụ in ra lý do thật khiến `[::1]` không mở được (đọc `relay.log`, tìm chương trình đang chiếm cổng IPv6, kiểm tra giá trị registry `DisabledComponents`) và tự kiểm tra kết quả phân giải tên miền.

## Tính năng chính

### 1. Kiểm tra và chẩn đoán kết nối Steam

- Kiểm tra phân giải DNS và kết nối HTTPS đến danh sách tên miền Steam được cấu hình trong công cụ.
- Phân biệt một số tình huống như không phân giải được DNS, kết nối TCP thất bại hoặc kết nối TLS/HTTPS gặp lỗi.
- Đối chiếu DNS của Windows với truy vấn DNS-over-HTTPS khi cần.
- Hiển thị trạng thái và kết quả theo từng tên miền để người dùng có thêm dữ liệu xác định nguyên nhân.
- Hiển thị trạng thái relay khi khởi động, gồm cả trạng thái cổng `[::1]` nếu phần MW4 đã được bật.

### 2. Local TCP relay thử nghiệm cho kết nối TLS/SNI

SteamFix có thể thử chạy một relay TCP cục bộ tại `127.0.0.1`, sau đó kiểm tra nhiều cách gửi phần mở đầu TLS (**ClientHello**) với cách chia dữ liệu khác nhau.

Nếu một tên miền vượt qua bước kiểm tra, công cụ có thể đề xuất chuyển hướng tên miền đó qua relay bằng một khối riêng trong file `hosts`. Relay được thiết kế để chuyển tiếp dữ liệu TLS, không giải mã nội dung HTTPS. Relay chỉ chấp nhận các tên miền thuộc danh sách cho phép (các tên miền Steam và `*.cdn.callofduty.com`); kết nối tới tên miền khác sẽ bị từ chối.

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
- **MW4 / IPv6:** kiểm tra máy có IPv6 thực hay không, dòng `hosts` của MW4, Windows đang phân giải tên miền CDN ra địa chỉ nào, relay có đang nghe trên `127.0.0.1` và `[::1]` hay không (xem mục 7).
- **QUIC:** tùy chọn thêm hoặc gỡ quy tắc Windows Firewall chặn UDP cổng 443 cho `steamwebhelper.exe`, nhằm thử buộc trình duyệt Steam dùng TCP khi gặp vấn đề tương thích. Đây không phải lựa chọn cần bật mặc định.

### 7. Sửa lỗi MW4 Texture Streamer (IPv6) — mới từ v5.1

**Nguyên nhân được công cụ nhắm tới:** trên máy không có IPv6 thực, Windows có thể đưa cho game địa chỉ IPv4 ở dạng IPv4-bọc (`::ffff:a.b.c.d`). Khi đó game không mở được socket và không tải được texture.

**Cách xử lý (mục `[14]`):**
- Chạy lại quy trình cài relay như mục `[1]` (kiểm tra cả các tên miền Steam nên mất khoảng vài chục giây) và thêm tên miền `cod-assets.cdn.callofduty.com` vào danh sách thử.
- Relay nghe thêm trên `[::1]:443` (HTTPS) và `[::1]:80` (HTTP).
- Khối SteamFix trong `hosts` được ghi thêm hai dòng cho tên miền CDN của game: `127.0.0.1 cod-assets.cdn.callofduty.com` và `::1 cod-assets.cdn.callofduty.com`. Nhờ dòng `::1`, game nhận địa chỉ IPv6 thật thay vì dạng `::ffff:a.b.c.d`; relay chuyển tiếp byte TLS tới IP IPv4 thật của CDN.
- Công cụ chỉ ghi `hosts` sau khi người dùng xác nhận. Nếu tên miền CDN của game không tới được qua relay, phần MW4 được bỏ qua và phần Steam vẫn được cài bình thường.
- Chạy lại `[1]` sẽ giữ nguyên phần MW4 đã bật trước đó; mục `[4]` gỡ cả phần MW4.
- Sau khi cài xong, hãy **tắt hẳn game** (và launcher Battle.net nếu đang mở) rồi mở lại.

**Chế độ dự phòng (v5.2):** relay mở `[::1]` sau khi đã mở `127.0.0.1`, và công cụ chờ tối đa khoảng 5 giây. Nếu `[::1]` vẫn không nghe được (ví dụ cổng bị chương trình khác chiếm hoặc hệ điều hành không hỗ trợ IPv6), công cụ:
- Chỉ ghi dòng `127.0.0.1` cho MW4 (không ghi dòng `::1`), thay vì bỏ hẳn MW4.
- Hiển thị cảnh báo rằng chế độ này chỉ chạy nếu game chấp nhận `127.0.0.1`; nếu game vẫn nhận dạng `::ffff:127.0.0.1` thì texture vẫn sẽ không tải.
- In lý do thật khiến `[::1]` không mở được và gợi ý bước tiếp theo.
- Hướng dẫn xác nhận bằng cách mở game rồi chọn `[15]`: mục `[5]` phải có dòng `ok=` thì game mới thực sự đã kết nối tới relay. Sau khi xử lý nguyên nhân bind `[::1]`, chọn lại `[14]` để cài với dòng `::1`.

**Chẩn đoán (mục `[15]`, chỉ đọc, không sửa gì):**
1. IPv6 của máy: có địa chỉ IPv6 toàn cầu hay không, giá trị `DisabledComponents`.
2. Các dòng `hosts` liên quan đến tên miền CDN của game.
3. Windows đang phân giải tên miền CDN ra địa chỉ nào (như game sẽ thấy).
4. Relay có đang nghe trên `127.0.0.1:443`, `127.0.0.1:80`, `[::1]:443`, `[::1]:80` hay không.
5. Các dòng `relay.log` nhắc tới MW4 hoặc `[::1]`.
6. CDN thật có tới được trực tiếp hay không (IP lấy qua DNS mã hóa, không đi qua relay).

Dấu hiệu thành công: thư mục cache texture của game bắt đầu có file, và `relay.log` có dòng `stat cod-assets... ok=N` (xem bằng `[10]`).

## Cách sử dụng

1. Tải `STEAM FIX.bat` từ repository về máy Windows.
2. Kiểm tra mã nguồn trước khi chạy, đặc biệt vì công cụ cần quyền Administrator để thực hiện một số tác vụ hệ thống.
3. Chạy file và chấp thuận yêu cầu quyền quản trị nếu muốn tiếp tục.
4. Đọc phần kiểm tra trạng thái xuất hiện lúc khởi động, sau đó chọn chức năng trong menu.
5. Nếu muốn thử phương án tổng thể, chọn **`[1] SUA TOAN DIEN`**. Công cụ sẽ kiểm tra các tên miền, thử cài relay và yêu cầu xác nhận trước khi ghi các ánh xạ relay vào `hosts`.
6. Nếu cần tìm nguyên nhân thay vì thay đổi cấu hình, ưu tiên các mục chẩn đoán như **`[2]`**, **`[3]`**, **`[11]`**, **`[12]`**, **`[13]`** hoặc **`[15]`**.
7. Nếu game MW4 không tải được texture: chọn **`[15]`** để xem tình trạng, chọn **`[14]`** để bật sửa lỗi, tắt hẳn rồi mở lại game, sau đó chọn **`[15]`** một lần nữa để xác nhận.

### Menu chức năng

| Mục | Chức năng |
|---|---|
| `[1]` | Sửa tổng thể: DNS, DoH nếu hỗ trợ, kiểm tra/cài relay, kiểm tra kết nối và khởi động lại Steam; giữ nguyên phần MW4 nếu đã bật trước đó |
| `[2]` | Quét lại kết nối và xem trạng thái DNS/relay (kèm trạng thái `[::1]` nếu đã bật MW4) |
| `[3]` | Thử nghiệm các cách chia TLS ClientHello |
| `[4]` | Gỡ relay, khối `hosts` do SteamFix quản lý (kể cả dòng MW4) và xóa thư mục dữ liệu relay |
| `[5]` | Dọn cache web/HTTP/avatar của Steam và khởi động lại |
| `[6]` | Chỉ đặt DNS Google/Cloudflare và thử bật DoH |
| `[7]` | Đặt DNS adapter về chế độ tự động |
| `[8]` / `[9]` | Bật / gỡ quy tắc chặn QUIC cho SteamWebHelper |
| `[10]` | Xem log relay |
| `[11]` | Chẩn đoán dấu hiệu lọc theo SNI hay IP |
| `[12]` | Chẩn đoán kết nối máy chủ tải game |
| `[13]` | Chẩn đoán avatar và đường kết nối CDN |
| `[14]` | **Mới:** sửa MW4 Texture Streamer (IPv6): relay `[::1]` cho `cod-assets.cdn.callofduty.com`, có chế độ dự phòng nếu `[::1]` không mở được |
| `[15]` | **Mới:** chẩn đoán MW4 / IPv6 (chỉ đọc, không sửa gì) |
| `[0]` | Thoát |

## Yêu cầu và cách hoạt động

- Windows với Windows PowerShell và các thành phần mạng/lập lịch tác vụ được công cụ sử dụng.
- Quyền **Administrator** cho các thao tác thay đổi DNS, `hosts`, firewall hoặc Scheduled Task.
- Kết nối Internet để kiểm tra các dịch vụ DNS công cộng và máy chủ Steam.
- Không yêu cầu cài Python hoặc tải riêng một thư viện relay: phần C# được biên dịch tại chỗ bằng cơ chế .NET `Add-Type` của PowerShell.
- Hỗ trợ DoH phụ thuộc phiên bản Windows và các lệnh quản lý DNS có sẵn trên hệ thống.
- Phần MW4 cần hệ điều hành hỗ trợ IPv6 loopback (`::1`) để chạy đầy đủ; nếu không, công cụ lùi về chế độ dự phòng như mô tả ở mục 7.

## Những thay đổi hệ thống cần biết

Trước khi chạy, hãy lưu ý SteamFix có thể thực hiện các thao tác sau tùy mục được chọn:
- Thay đổi DNS của các adapter mạng đang được công cụ chọn xử lý; cấu hình DoH có thể được đăng ký trong Windows.
- Tạo Scheduled Task tên **`SteamFix Relay`**, chạy relay bằng tài khoản hệ thống khi khởi động hoặc đăng nhập.
- Lắng nghe cổng TCP cục bộ `127.0.0.1:443` và, khi bật phần HTTP, `127.0.0.1:80`.
- Khi bật sửa lỗi MW4 (`[14]`): lắng nghe thêm trên IPv6 loopback `[::1]:443` và `[::1]:80`.
- Ghi khối ánh xạ tên miền Steam vào file `hosts`, sau khi người dùng xác nhận. Với MW4, khối này có thêm dòng `127.0.0.1` và (nếu relay nghe được `[::1]`) dòng `::1` cho `cod-assets.cdn.callofduty.com`.
- Xóa cache web/HTTP/avatar của Steam khi chọn chức năng dọn cache.
- Thêm quy tắc Windows Firewall nếu người dùng bật tùy chọn chặn QUIC.

**Gỡ relay không đồng nghĩa mọi cấu hình đều tự quay về trạng thái trước đó.** Mục `[4]` gỡ Scheduled Task, khối `hosts` do công cụ quản lý (kể cả dòng MW4) và **xóa thư mục `%ProgramData%\SteamFix\`, bao gồm cả log**; nếu đã bật MW4, hãy khởi động lại game sau khi gỡ. Nếu đã bật chặn QUIC thì dùng `[9]` để gỡ quy tắc đó. Mục `[7]` đặt DNS adapter về tự động, không khôi phục chính xác DNS tĩnh tùy chỉnh trước đây. Hãy ghi lại cấu hình mạng ban đầu nếu máy đang dùng DNS hoặc thiết lập đặc biệt.

## Giới hạn

- SteamFix không sửa lỗi máy chủ Steam, lỗi tài khoản, lỗi game hoặc lỗi cài đặt ứng dụng.
- Việc đổi DNS không tự giải quyết được mọi vấn đề TLS/SNI hoặc chặn theo IP.
- Relay chỉ áp dụng cho các tên miền được kiểm tra và cấu hình; các kết nối Steam khác có thể không đi qua relay.
- Phần MW4 chỉ áp dụng cho tên miền `cod-assets.cdn.callofduty.com` và chỉ nhắm tới lỗi socket do địa chỉ IPv4-bọc; nó không sửa các lỗi khác của game hoặc launcher.
- Chế độ dự phòng của MW4 (chỉ có dòng `127.0.0.1`) **không bảo đảm chạy**; chỉ coi là hoạt động khi `[15]` cho thấy `relay.log` có dòng `ok=` sau khi mở game.
- Kết quả chẩn đoán là dấu hiệu kỹ thuật để khoanh vùng nguyên nhân, không phải bằng chứng tuyệt đối về chính sách của nhà mạng.
- Nếu relay không thể kết nối tới máy chủ đích, hoặc kiểu lọc mạng không phù hợp với cơ chế chia TLS, công cụ có thể không khắc phục được lỗi.

## Nhật ký

Dữ liệu và log của relay được lưu trong:

```text
%ProgramData%\SteamFix\
```

Trong đó có thể có `relay.log`, `relay-error.log` và dữ liệu hỗ trợ relay. Các log hữu ích khi gửi báo lỗi; hãy kiểm tra và che thông tin cá nhân hoặc dữ liệu nhạy cảm trước khi công khai. Lưu ý mục `[4]` xóa cả thư mục này, nên hãy sao lưu log trước nếu cần gửi báo lỗi.

## Đóng góp và báo lỗi

Khi báo lỗi, vui lòng mô tả phiên bản Windows, nhà mạng hoặc loại kết nối đang dùng, triệu chứng gặp phải và mục menu đã chạy. Với lỗi MW4, hãy kèm kết quả của mục `[15]`. Nếu đính kèm log, chỉ chia sẻ phần cần thiết và xóa thông tin riêng tư trước khi đăng.

## Tuyên bố miễn trừ trách nhiệm

Công cụ được cung cấp cho mục đích chẩn đoán và khắc phục sự cố kết nối trên máy của người dùng. Hãy đọc mã nguồn trước khi chạy và tự đánh giá các thay đổi hệ thống mà công cụ đề xuất. Tác giả không bảo đảm công cụ sẽ hoạt động trên mọi cấu hình mạng hoặc chịu trách nhiệm cho các thay đổi do người dùng chủ động xác nhận.

---

**Author:** TimmyHeart - V — Tran Hieu Nghia
