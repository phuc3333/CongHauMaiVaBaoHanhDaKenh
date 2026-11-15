package haumai.core.repository;

import org.springframework.jdbc.core.ConnectionCallback;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.sql.CallableStatement;
import java.sql.Types;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.UUID;

@Repository
public class ConversationRepository {
    private final JdbcTemplate jdbc;

    public ConversationRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public List<Map<String, Object>> conversationMessages(Long id) {
        return jdbc.queryForList("""
            SELECT huong_tin, noi_dung, trang_thai_gui,
                   TO_CHAR(tao_luc AT TIME ZONE 'Asia/Ho_Chi_Minh', 'YYYY-MM-DD HH24:MI:SS') AS thoi_gian
            FROM public.v_tin_nhan_cuoc_tro_chuyen
            WHERE cuoc_tro_chuyen_id = ? AND ma_kenh IN ('FACEBOOK', 'ZALO')
            ORDER BY tao_luc, id
            """, id);
    }

    public List<Map<String, Object>> unlinkedConversations() {
        return jdbc.queryForList("""
            SELECT id, ma_kenh, ma_nguoi_dung_kenh, ho_so_id, tin_moi_nhat,
                   TO_CHAR(cap_nhat_luc AT TIME ZONE 'Asia/Ho_Chi_Minh', 'YYYY-MM-DD HH24:MI:SS') AS cap_nhat_luc
            FROM public.v_cuoc_tro_chuyen
            WHERE ma_kenh IN ('FACEBOOK', 'ZALO') AND ho_so_id IS NULL
            ORDER BY cap_nhat_luc DESC LIMIT 100
            """);
    }

    public List<Map<String, Object>> caseMessages(Long id) {
        return jdbc.queryForList("""
            SELECT huong_tin, noi_dung, trang_thai_gui, thoi_gian
            FROM (
                SELECT huong_tin, noi_dung, trang_thai_gui,
                       TO_CHAR(tao_luc AT TIME ZONE 'Asia/Ho_Chi_Minh', 'YYYY-MM-DD HH24:MI:SS') AS thoi_gian
                FROM public.v_tin_nhan_facebook WHERE ho_so_id = ?
                UNION ALL
                SELECT huong_tin, noi_dung, trang_thai_gui,
                       TO_CHAR(tao_luc AT TIME ZONE 'Asia/Ho_Chi_Minh', 'YYYY-MM-DD HH24:MI:SS') AS thoi_gian
                FROM public.v_tin_nhan_zalo WHERE ho_so_id = ?
            ) messages ORDER BY thoi_gian
            """, id, id);
    }

    public Map<String, Object> conversationIdentity(Long conversationId) {
        return jdbc.queryForMap("""
            SELECT ma_kenh, ma_nguoi_dung_kenh FROM public.v_cuoc_tro_chuyen
            WHERE id = ? AND ma_kenh IN ('FACEBOOK', 'ZALO')
            """, conversationId);
    }

    public Long activeCskhId(String username) {
        return jdbc.queryForObject("""
            SELECT nv.id FROM public.nhan_vien nv
            JOIN public.tai_khoan tk ON tk.id = nv.tai_khoan_id
            WHERE tk.ten_dang_nhap = ? AND tk.vai_tro = 'CSKH' AND tk.dang_hoat_dong = TRUE
            """, Long.class, username);
    }

    public ReplyTarget createConversationReply(Long conversationId, Long employeeId, String content,
                                               OffsetDateTime now) {
        return jdbc.execute((ConnectionCallback<ReplyTarget>) connection -> {
            try (CallableStatement call = connection.prepareCall(
                "{call public.sp_tao_phan_hoi_cuoc_tro_chuyen(?, ?, ?, ?, ?, ?, ?)}")) {
                call.setLong(1, conversationId);
                call.setLong(2, employeeId);
                call.setString(3, content);
                call.setObject(4, now);
                call.registerOutParameter(5, Types.BIGINT);
                call.registerOutParameter(6, Types.VARCHAR);
                call.registerOutParameter(7, Types.VARCHAR);
                call.execute();
                return new ReplyTarget(call.getLong(5), call.getString(6), call.getString(7));
            }
        });
    }

    public CreatedCase createCaseFromConversation(Long conversationId, String name, String phone,
                                                  String description, String serial, OffsetDateTime now) {
        Map<String, Object> identity = conversationIdentity(conversationId);
        String channel = identity.get("ma_kenh").toString();
        String senderId = identity.get("ma_nguoi_dung_kenh").toString();
        String externalId = "CSKH-FORM-" + conversationId + "-" + UUID.randomUUID();
        return jdbc.execute((ConnectionCallback<CreatedCase>) connection -> {
            try (CallableStatement updateCustomer = connection.prepareCall(
                "{call public.sp_cap_nhat_khach_hang_tu_dinh_danh(?, ?, ?, ?)}")) {
                updateCustomer.setString(1, channel);
                updateCustomer.setString(2, senderId);
                updateCustomer.setString(3, name);
                updateCustomer.setString(4, phone);
                updateCustomer.execute();
            }
            long caseId;
            String caseNumber;
            try (CallableStatement create = connection.prepareCall(
                "{call public.sp_tao_ho_so_da_kenh(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)}")) {
                create.setString(1, channel);
                create.setString(2, externalId);
                create.setString(3, senderId);
                create.setString(4, name);
                create.setString(5, phone);
                create.setNull(6, Types.VARCHAR);
                create.setString(7, serial);
                create.setString(8, description);
                create.setObject(9, now);
                create.registerOutParameter(10, Types.BIGINT);
                create.registerOutParameter(11, Types.VARCHAR);
                create.execute();
                caseId = create.getLong(10);
                caseNumber = create.getString(11);
            }
            try (CallableStatement link = connection.prepareCall(
                "{call public.sp_gan_cuoc_tro_chuyen_vao_ho_so(?, ?, ?)}")) {
                link.setString(1, channel);
                link.setString(2, senderId);
                link.setLong(3, caseId);
                link.execute();
            }
            try (CallableStatement linkPending = connection.prepareCall(
                "{call public.sp_gan_tin_cho_bo_sung_vao_ho_so(?, ?, ?)}")) {
                linkPending.setString(1, channel);
                linkPending.setString(2, senderId);
                linkPending.setLong(3, caseId);
                linkPending.execute();
            }
            return new CreatedCase(caseId, caseNumber);
        });
    }

    public ReplyTarget createCaseReply(Long caseId, Long employeeId, String content,
                                       String channel, OffsetDateTime now) {
        String procedure = "ZALO".equals(channel)
            ? "{call public.sp_tao_phan_hoi_zalo(?, ?, ?, ?, ?, ?)}"
            : "{call public.sp_tao_phan_hoi_facebook(?, ?, ?, ?, ?, ?)}";
        return jdbc.execute((ConnectionCallback<ReplyTarget>) connection -> {
            try (CallableStatement call = connection.prepareCall(procedure)) {
                call.setLong(1, caseId);
                call.setLong(2, employeeId);
                call.setString(3, content);
                call.setObject(4, now);
                call.registerOutParameter(5, Types.BIGINT);
                call.registerOutParameter(6, Types.VARCHAR);
                call.execute();
                return new ReplyTarget(call.getLong(5), channel, call.getString(6));
            }
        });
    }

    public record ReplyTarget(Long messageId, String channel, String recipient) {}
    public record CreatedCase(Long caseId, String caseNumber) {}
}
