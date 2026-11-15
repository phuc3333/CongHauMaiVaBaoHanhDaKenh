package haumai.core.repository;

import haumai.contract.InboundChannelReply;
import org.springframework.jdbc.core.ConnectionCallback;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import java.sql.CallableStatement;
import java.sql.Types;
import java.time.OffsetDateTime;
import java.time.ZoneId;

@Repository
public class InboundReplyRepository {
    private final JdbcTemplate jdbc;
    public InboundReplyRepository(JdbcTemplate jdbc) { this.jdbc = jdbc; }
    private OffsetDateTime receivedAt(InboundChannelReply m) {
        return m.nhanLuc() == null ? OffsetDateTime.now(ZoneId.of("Asia/Ho_Chi_Minh")) : m.nhanLuc();
    }
    public boolean isChannelEnabled(String channel) {
        return !jdbc.queryForList("SELECT ma_kenh FROM public.v_kenh_tich_hop WHERE ma_kenh = ? AND dang_bat = TRUE", channel).isEmpty();
    }
    public ExistingMessage findExisting(String channel, String externalId) {
        return jdbc.query("SELECT ho_so_id, ma_ho_so FROM public.v_tin_nhan_kenh_goc WHERE ma_kenh = ? AND ma_tin_goc = ?",
            rs -> rs.next() ? new ExistingMessage(rs.getLong("ho_so_id"), rs.getString("ma_ho_so")) : null,
            channel, externalId);
    }
    public LinkFacts findLinkFacts(String channel, String senderId) {
        return jdbc.query("""
            SELECT so_ho_so_mo, ho_so_id, ma_ho_so FROM public.v_ho_so_mo_theo_dinh_danh_kenh
            WHERE ma_kenh = ? AND ma_nguoi_dung_kenh = ?
            """, rs -> {
                if (!rs.next()) return null;
                long caseId = rs.getLong("ho_so_id");
                Long nullableCaseId = rs.wasNull() ? null : caseId;
                return new LinkFacts(rs.getInt("so_ho_so_mo"), nullableCaseId, rs.getString("ma_ho_so"));
            }, channel, senderId);
    }
    public boolean saveClassifiedMessage(InboundChannelReply message, Long caseId, String channel) {
        return jdbc.execute((ConnectionCallback<Boolean>) c -> {
            try (CallableStatement call = c.prepareCall("{call public.sp_luu_tin_nhan_da_phan_loai(?, ?, ?, ?, ?, ?)}")) {
                call.setString(1, channel); call.setString(2, message.maTinGoc()); call.setLong(3, caseId);
                call.setString(4, message.noiDung().trim()); call.setObject(5, receivedAt(message));
                call.registerOutParameter(6, Types.BOOLEAN); call.execute(); return call.getBoolean(6);
            }
        });
    }
    public void saveConversation(InboundChannelReply m, Long caseId) {
        jdbc.execute((ConnectionCallback<Void>) c -> {
            try (CallableStatement call=c.prepareCall("{call public.sp_luu_tin_cuoc_tro_chuyen(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)}")) {
                call.setString(1,m.maKenh()); call.setString(2,m.maNguoiDungKenh()); call.setString(3,m.maTinGoc());
                call.setString(4,m.noiDung()); call.setString(5,"DEN");
                if(caseId==null) call.setNull(6,Types.BIGINT); else call.setLong(6,caseId);
                call.setNull(7,Types.BIGINT); call.setObject(8,receivedAt(m));
                call.registerOutParameter(9,Types.BIGINT); call.registerOutParameter(10,Types.BIGINT); call.execute();
            } return null;
        });
    }
    public void saveForFollowUp(InboundChannelReply m, String reason) {
        jdbc.execute((ConnectionCallback<Void>) c -> {
            try (CallableStatement call=c.prepareCall("{call public.sp_luu_tin_cho_bo_sung(?, ?, ?, ?, ?, ?)}")) {
                call.setString(1,m.maKenh()); call.setString(2,m.maTinGoc()); call.setString(3,m.maNguoiDungKenh());
                call.setString(4,m.noiDung()); call.setString(5,"CAN_FORM".equals(reason)||"CHUA_CO_DINH_DANH".equals(reason)?"CAN_FORM":reason);
                call.setObject(6,receivedAt(m)); call.execute();
            } return null;
        });
    }
    public record ExistingMessage(Long caseId, String caseNumber) {}
    public record LinkFacts(Integer openCaseCount, Long caseId, String caseNumber) {}
}
