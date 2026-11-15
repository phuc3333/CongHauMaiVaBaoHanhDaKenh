# HauMai Care

HauMai Care là hệ thống tiếp nhận và quản lý yêu cầu hậu mãi, bảo hành từ các kênh nhắn tin. Nhân viên CSKH tiếp nhận và xác minh hồ sơ; điều phối viên phân công kỹ thuật viên và theo dõi SLA; kỹ thuật viên tiếp nhận và hoàn tất sửa chữa.

## Chức năng chính

- Khách hàng tra cứu bảo hành bằng serial và tra cứu tiến độ hồ sơ bằng mã hồ sơ cùng số điện thoại.
- CSKH quản lý hội thoại, tạo và cập nhật hồ sơ, xác minh thông tin bảo hành, phản hồi khách hàng và đóng hồ sơ.
- Điều phối viên xem hàng đợi, phân công hoặc đổi kỹ thuật viên và theo dõi các mốc SLA.
- Kỹ thuật viên xem việc được giao, tiếp nhận phân công và ghi nhận hoàn tất sửa chữa.
- Tiếp nhận và phản hồi tin nhắn qua các kênh được cấu hình. Zalo có trang mô phỏng phục vụ demo.

## Kiến trúc

```mermaid
flowchart LR
    Browser[Trình duyệt] --> Core["warranty-core<br/>Giao diện và nghiệp vụ<br/>Cổng 8080"]
    Channels[Kênh nhắn tin] --> Gateway["channel-gateway<br/>Webhook và gửi phản hồi<br/>Cổng 8081 nội bộ"]
    Core <--> Streams[(Redis Streams)]
    Gateway <--> Streams
    Core --> DB[(PostgreSQL)]
```

Trong `warranty-core`, mã nguồn được tổ chức theo ba tầng: Controller, Service và Repository. Ứng dụng `channel-gateway` tiếp nhận webhook và gửi phản hồi; hai ứng dụng trao đổi thông điệp qua Redis Streams. Chỉ `warranty-core` kết nối PostgreSQL. Lược đồ được cập nhật bằng Flyway migrations.

## Công nghệ

- Java 21, Spring Boot 3.4.5, Maven
- PostgreSQL 16, Flyway
- Redis 7 Streams
- Docker và Docker Compose
- Thymeleaf, Spring MVC và Spring Security

## Yêu cầu

- Docker Desktop đang chạy với Linux containers.
- Git để tải mã nguồn.
- Các cổng máy chủ `5433`, `6379`, `8080` và `8081` chưa được ứng dụng khác sử dụng.

## Chạy bằng Docker Compose

1. Tải mã nguồn và vào thư mục dự án:

   ```powershell
   git clone https://github.com/phuc3333/CongHauMaiVaBaoHanhDaKenh.git
   cd CongHauMaiVaBaoHanhDaKenh
   ```

2. Tạo file `.env` ở thư mục gốc với cấu hình local sau; thay các giá trị mật khẩu/chuỗi bí mật trước khi chạy:

   ```dotenv
   HAU_MAI_DB_PASSWORD=mat_khau_postgres_local
   HAU_MAI_APP_PASSWORD=mat_khau_ung_dung_local
   ZALO_APP_ID=local-demo-app
   ZALO_OA_WEBHOOK_SECRET=chuoi_bi_mat_demo_local
   ZALO_DEMO_ENABLED=true
   ZALO_SENDER=fake
   ```

   Không commit hoặc gửi file `.env` lên GitHub. Các biến Facebook và Zalo OA thật chỉ cần cấu hình nếu kết nối tài khoản kênh thật.

3. **Chỉ với CSDL mới chưa có dữ liệu**, tạo các vai trò PostgreSQL mà migration cần. Khởi động PostgreSQL:

   ```powershell
   docker compose up -d postgres
   docker compose ps
   ```

   Khi PostgreSQL đã sẵn sàng, mở phiên `psql`:

   ```powershell
   docker compose exec postgres psql -U hau_mai -d hau_mai
   ```

   Nhập các dòng sau. Khi được hỏi mật khẩu cho `hau_mai_app`, nhập đúng giá trị `HAU_MAI_APP_PASSWORD` trong `.env`:

   ```sql
   CREATE ROLE hau_mai_owner NOLOGIN;
   CREATE ROLE hau_mai_app LOGIN;
   \password hau_mai_app
   \q
   ```

   Nếu dùng volume CSDL đã được thiết lập trước đó và hai vai trò này đã tồn tại, bỏ qua bước tạo vai trò.

4. Khởi động toàn bộ dịch vụ:

   ```powershell
   docker compose up -d --build
   docker compose ps
   ```

   Đợi PostgreSQL, Redis, `warranty-core` và `channel-gateway` chuyển sang trạng thái đang chạy. `warranty-core` áp dụng migration Flyway khi khởi động.

   Các mật khẩu trong `.env` được áp dụng khi PostgreSQL tạo volume dữ liệu lần đầu. Nếu volume đã được tạo từ trước, đổi mật khẩu trong `.env` không tự đổi mật khẩu đã lưu trong PostgreSQL.

5. Mở hệ thống:

   | Nội dung | Địa chỉ |
   |---|---|
   | Trang chính | <http://localhost:8080> |
   | Đăng nhập nhân viên | <http://localhost:8080/login> |
   | Kiểm tra bảo hành | <http://localhost:8080/khach/kiem-tra-bao-hanh> |
   | Tra cứu hồ sơ | <http://localhost:8080/khach/tra-cuu> |
   | Zalo mô phỏng | <http://localhost:8081/zalo-demo.html> |

   Tài khoản demo được tạo bởi các migration seed. Các tên đăng nhập mẫu gồm `cskh`, `quanly`, `ktv01`, `ktv02` và `ktv03`. Mật khẩu được lưu dưới dạng băm trong cơ sở dữ liệu; dùng thông tin đăng nhập demo được cấp cho môi trường của bạn.

## Demo Zalo

Trang Zalo mô phỏng chạy tại `http://localhost:8081/zalo-demo.html`. Nhập số điện thoại demo và gửi tin nhắn đầu tiên theo định dạng:

```text
Họ tên: Nguyễn Minh Anh
Serial: HM-RO-2026-007
Mô tả lỗi: Máy lọc nước bị rò nước
```

Để gửi tin tiếp theo của cùng khách, giữ nguyên số điện thoại và gửi nội dung trao đổi. Luồng mô phỏng không cần tài khoản Zalo OA thật. Để nhận/gửi tin với kênh thật, cần cấu hình thông tin xác thực và endpoint webhook phù hợp của nền tảng.

## Quản lý dịch vụ

Xem trạng thái dịch vụ:

```powershell
docker compose ps
```

Xem log:

```powershell
docker compose logs -f warranty-core
docker compose logs -f channel-gateway
```

Dừng các dịch vụ nhưng giữ dữ liệu:

```powershell
docker compose down
```

Dữ liệu PostgreSQL và Redis được lưu trong Docker volumes. Không thêm `-v` vào lệnh `docker compose down` nếu muốn giữ dữ liệu.

## Cấu trúc thư mục

```text
channel-contract/           Cấu trúc thông điệp dùng chung
channel-gateway/            Webhook và tích hợp kênh
database/schema-current.sql  Ảnh chụp lược đồ PostgreSQL
warranty-core/              Giao diện, nghiệp vụ, repository và Flyway migrations
docker-compose.yml          Cấu hình chạy các dịch vụ
```

## Ghi chú

- Docker build hiện đóng gói ứng dụng với `-DskipTests`; lệnh chạy hệ thống không đồng nghĩa với việc các nghiệp vụ đã được kiểm thử tự động.
- Không đưa mật khẩu, token của Facebook/Zalo hoặc file `.env` lên repository.
