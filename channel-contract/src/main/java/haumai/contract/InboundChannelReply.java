package haumai.contract;

import java.time.OffsetDateTime;

public record InboundChannelReply(
    String maKenh,
    String maTinGoc,
    String maNguoiDungKenh,
    String noiDung,
    OffsetDateTime nhanLuc
) {
}
