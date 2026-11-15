package haumai.core.repository;

import haumai.contract.InboundChannelMessage;
import org.springframework.jdbc.core.ConnectionCallback;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import java.sql.CallableStatement;
import java.sql.Types;
import java.time.OffsetDateTime;
import java.time.ZoneId;

@Repository
public class InboundChannelRepository {
    private final JdbcTemplate jdbc;
    public InboundChannelRepository(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    public CreationResult createCase(InboundChannelMessage message) {
        return jdbc.execute((ConnectionCallback<CreationResult>) connection -> {
            try (CallableStatement call = connection.prepareCall("{call public.sp_tao_ho_so_da_kenh(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)}")) {
                call.setString(1, message.maKenh()); call.setString(2, message.maTinGoc());
                call.setString(3, message.maNguoiDungKenh()); call.setString(4, message.hoTen());
                call.setString(5, message.soDienThoai()); call.setString(6, message.email());
                call.setString(7, message.serial()); call.setString(8, message.noiDung());
                OffsetDateTime receivedAt = message.nhanLuc() == null
                    ? OffsetDateTime.now(ZoneId.of("Asia/Ho_Chi_Minh")) : message.nhanLuc();
                call.setObject(9, receivedAt); call.registerOutParameter(10, Types.BIGINT);
                call.registerOutParameter(11, Types.VARCHAR); call.execute();
                long caseId = call.getLong(10); String caseNumber = call.getString(11);
                if (message.maNguoiDungKenh() != null && !message.maNguoiDungKenh().isBlank()) {
                    try (CallableStatement save = connection.prepareCall("{call public.sp_luu_tin_cuoc_tro_chuyen(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)}")) {
                        save.setString(1, message.maKenh()); save.setString(2, message.maNguoiDungKenh());
                        save.setString(3, message.maTinGoc()); save.setString(4, message.noiDung());
                        save.setString(5, "DEN"); save.setLong(6, caseId); save.setNull(7, Types.BIGINT);
                        save.setObject(8, receivedAt); save.registerOutParameter(9, Types.BIGINT);
                        save.registerOutParameter(10, Types.BIGINT); save.execute();
                    }
                    try (CallableStatement link = connection.prepareCall("{call public.sp_gan_cuoc_tro_chuyen_vao_ho_so(?, ?, ?)}")) {
                        link.setString(1, message.maKenh()); link.setString(2, message.maNguoiDungKenh());
                        link.setLong(3, caseId); link.execute();
                    }
                    try (CallableStatement linkPending = connection.prepareCall("{call public.sp_gan_tin_cho_bo_sung_vao_ho_so(?, ?, ?)}")) {
                        linkPending.setString(1, message.maKenh()); linkPending.setString(2, message.maNguoiDungKenh());
                        linkPending.setLong(3, caseId); linkPending.execute();
                    }
                }
                return new CreationResult(caseId, caseNumber);
            }
        });
    }
    public record CreationResult(long caseId, String caseNumber) {}
}
