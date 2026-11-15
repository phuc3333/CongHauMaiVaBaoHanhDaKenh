package haumai.contract;

import java.time.OffsetDateTime;

/**
 * Normalized inbound message shared by channel-gateway and warranty-core.
 * The gateway publishes this payload to Redis; warranty-core consumes it.
 */
public record InboundChannelMessage(
    String maKenh,
    String maTinGoc,
    String maNguoiDungKenh,
    String hoTen,
    String soDienThoai,
    String email,
    String serial,
    String noiDung,
    OffsetDateTime nhanLuc
) {
}