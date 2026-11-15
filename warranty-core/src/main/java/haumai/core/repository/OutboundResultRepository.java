package haumai.core.repository;

import org.springframework.jdbc.core.ConnectionCallback;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import java.sql.CallableStatement;
import java.time.OffsetDateTime;

@Repository
public class OutboundResultRepository {
    private final JdbcTemplate jdbc;
    public OutboundResultRepository(JdbcTemplate jdbc) { this.jdbc=jdbc; }
    public void update(long messageId, String status, String externalId, String channel, boolean conversation) {
        String procedure = conversation ? "{call public.sp_cap_nhat_gui_cuoc_tro_chuyen(?, ?, ?, ?)}"
            : switch(channel.toUpperCase(java.util.Locale.ROOT)) {
                case "ZALO" -> "{call public.sp_cap_nhat_ket_qua_gui_zalo(?, ?, ?, ?)}";
                case "FACEBOOK" -> "{call public.sp_cap_nhat_ket_qua_gui_facebook(?, ?, ?, ?)}";
                default -> throw new IllegalArgumentException("Chưa hỗ trợ cập nhật kết quả kênh " + channel);
            };
        jdbc.execute((ConnectionCallback<Void>) c -> {
            try(CallableStatement call=c.prepareCall(procedure)) {
                call.setLong(1,messageId); call.setString(2,status); call.setString(3,externalId);
                call.setObject(4,OffsetDateTime.now(java.time.ZoneId.of("Asia/Ho_Chi_Minh"))); call.execute();
            } return null;
        });
    }
}
