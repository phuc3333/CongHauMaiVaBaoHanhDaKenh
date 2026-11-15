package haumai.core.repository;

import org.springframework.jdbc.core.ConnectionCallback;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.sql.CallableStatement;
import java.sql.Types;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;

/** Reads SLA facts and persists service decisions. Business rules stay in SlaService. */
@Repository
public class SlaRepository {
    private final JdbcTemplate jdbc;

    public SlaRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public List<Map<String, Object>> findByCaseId(Long caseId) {
        return jdbc.queryForList(
            "SELECT * FROM public.v_sla_service WHERE ho_so_id=? ORDER BY sla_id", caseId);
    }

    public List<Map<String, Object>> findRunning() {
        return jdbc.queryForList(
            "SELECT * FROM public.v_sla_service WHERE trang_thai='DANG_DEM' ORDER BY sla_id");
    }

    public void startRepairSla(long slaId, OffsetDateTime now) {
        jdbc.execute((ConnectionCallback<Void>) connection -> {
            try (CallableStatement call = connection.prepareCall(
                "{call public.sp_bat_dau_sla_sua_chua(?, ?, ?)}")) {
                call.setLong(1, slaId);
                call.setString(2, "CHUA_BAT_DAU");
                call.setObject(3, now);
                call.execute();
            }
            return null;
        });
    }

    public void save(long slaId, String oldStatus, String status, OffsetDateTime startAt,
                     OffsetDateTime endAt, long paused, OffsetDateTime pauseAt,
                     OffsetDateTime detectedAt, String violationNote, Long receiver,
                     String key, String title, String body, String type, OffsetDateTime now) {
        jdbc.execute((ConnectionCallback<Void>) connection -> {
            try (CallableStatement call = connection.prepareCall(
                "{call public.sp_luu_sla_tu_service(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)}")) {
                call.setLong(1, slaId);
                call.setString(2, oldStatus);
                call.setString(3, status);
                setTime(call, 4, startAt);
                setTime(call, 5, endAt);
                call.setLong(6, paused);
                setTime(call, 7, pauseAt);
                setTime(call, 8, detectedAt);
                setText(call, 9, violationNote);
                if (receiver == null) call.setNull(10, Types.BIGINT); else call.setLong(10, receiver);
                setText(call, 11, key);
                setText(call, 12, title);
                setText(call, 13, body);
                setText(call, 14, type);
                setTime(call, 15, now);
                call.execute();
            }
            return null;
        });
    }

    private static void setTime(CallableStatement call, int index, OffsetDateTime value)
        throws java.sql.SQLException {
        if (value == null) call.setNull(index, Types.TIMESTAMP_WITH_TIMEZONE);
        else call.setObject(index, value);
    }

    private static void setText(CallableStatement call, int index, String value)
        throws java.sql.SQLException {
        if (value == null) call.setNull(index, Types.VARCHAR);
        else call.setString(index, value);
    }
}
