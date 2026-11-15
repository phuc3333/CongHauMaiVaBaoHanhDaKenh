package haumai.core.service;

import haumai.core.repository.SlaRepository;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.util.List;
import java.util.Map;

/** Evaluates the two workflow SLAs in Java; database procedures only persist computed values. */
@Service
public class SlaService {
    private static final ZoneId ZONE = ZoneId.of("Asia/Ho_Chi_Minh");
    private final SlaRepository repository;

    public SlaService(SlaRepository repository) { this.repository = repository; }

    @Transactional
    public void onCaseTransition(Long caseId, String from, String to, OffsetDateTime now) {
        List<Map<String, Object>> rows = rows(caseId);
        for (Map<String, Object> row : rows) {
            String type = text(row, "loai_sla");
            String state = text(row, "trang_thai");
            long paused = number(row, "thoi_gian_tam_dung_phut");
            OffsetDateTime pauseAt = nullableTime(row.get("thoi_diem_tam_dung"));

            // Repair SLA exists from case creation but does not start until dispatch assigns a technician.
            if ("MOI".equals(from) && "DANG_XAC_MINH".equals(to)
                && "XU_LY".equals(type) && "DANG_DEM".equals(state)) {
                save(row, "CHUA_BAT_DAU", time(row.get("thoi_diem_bat_dau")), null,
                    paused, null, null, null, null, null, null, null, null, now);
            } else if ("TIEP_NHAN".equals(type)) {
                if ("CHO_KHACH_BO_SUNG".equals(to) && "DANG_DEM".equals(state)) {
                    save(row, "TAM_DUNG", time(row.get("thoi_diem_bat_dau")), null,
                        paused, now, null, null, null, null, null, null, null, now);
                } else if ("CHO_KHACH_BO_SUNG".equals(from) && "DANG_XAC_MINH".equals(to)
                    && "TAM_DUNG".equals(state) && pauseAt != null) {
                    paused += pausedMinutes(pauseAt, now);
                    save(row, "DANG_DEM", time(row.get("thoi_diem_bat_dau")), null,
                        paused, null, null, null, null, null, null, null, null, now);
                } else if (("DANG_XAC_MINH".equals(from)
                        && ("CHO_PHAN_CONG".equals(to) || "TU_CHOI".equals(to))
                        && ("DANG_DEM".equals(state) || "DA_QUA_HAN".equals(state)))
                    || ("DA_DONG".equals(to) && ("DANG_DEM".equals(state)
                        || "TAM_DUNG".equals(state) || "DA_QUA_HAN".equals(state)))) {
                    if ("TAM_DUNG".equals(state) && pauseAt != null) paused += pausedMinutes(pauseAt, now);
                    finish(row, state, paused, now);
                }
            } else if ("XU_LY".equals(type) && "DA_SUA_XONG".equals(to)
                && ("DANG_DEM".equals(state) || "DA_QUA_HAN".equals(state))) {
                finish(row, state, paused, now);
            }
        }
    }

    /** Called for idempotently redelivered cases already in verification. */
    @Transactional
    public void deferRepairUntilAssignment(Long caseId, OffsetDateTime now) {
        deferRepairSla(caseId, now);
    }

    @Transactional
    public void startRepairSla(Long caseId, OffsetDateTime now) {
        Map<String, Object> row = findSla(caseId, "XU_LY");
        if (row == null) throw new IllegalStateException("Không tìm thấy SLA sửa chữa của hồ sơ " + caseId);
        if ("DANG_DEM".equals(text(row, "trang_thai"))) return; // Reassignment does not restart the clock.
        if (!"CHUA_BAT_DAU".equals(text(row, "trang_thai")))
            throw new IllegalStateException("SLA sửa chữa không ở trạng thái chờ phân công");
        repository.startRepairSla(number(row, "sla_id"), now);
    }

    private void deferRepairSla(Long caseId, OffsetDateTime now) {
        Map<String, Object> row = findSla(caseId, "XU_LY");
        if (row != null && "DANG_DEM".equals(text(row, "trang_thai"))) {
            save(row, "CHUA_BAT_DAU", time(row.get("thoi_diem_bat_dau")), null,
                number(row, "thoi_gian_tam_dung_phut"), null, null, null, null, null, null, null, null, now);
        }
    }

    private void finish(Map<String, Object> row, String oldState, long paused, OffsetDateTime now) {
        String finalState = "DA_QUA_HAN".equals(oldState) || now.isAfter(deadline(row, paused))
            ? "KHONG_DAT_SLA" : "DAT_SLA";
        save(row, finalState, time(row.get("thoi_diem_bat_dau")), now,
            paused, null, null, null, null, null, null, null, null, now);
    }

    @Scheduled(fixedDelay = 30_000)
    @Transactional
    public void scan() {
        OffsetDateTime now = OffsetDateTime.now(ZONE);
        for (Map<String, Object> row : repository.findRunning()) {
            OffsetDateTime deadline = deadline(row, number(row, "thoi_gian_tam_dung_phut"));
            String type = text(row, "loai_sla");
            String caseNumber = text(row, "ma_ho_so");
            Long managerId = nullableNumber(row.get("nguoi_quan_ly_id"));
            double warningPercent = decimal(row.get("nguong_canh_bao"));
            if (warningPercent < 0 || warningPercent > 100)
                throw new IllegalStateException("Ngưỡng cảnh báo SLA phải nằm trong khoảng 0 đến 100");
            String notificationType = null, key = null, title = null, body = null;
            OffsetDateTime detectedAt = null, endAt = null;
            String status = "DANG_DEM";
            if (now.isAfter(deadline)) {
                status = "DA_QUA_HAN"; endAt = deadline; detectedAt = now;
                body = "SLA " + type + " của hồ sơ " + caseNumber + " đã quá hạn.";
                title = "Hồ sơ quá hạn SLA"; key = "sla_qua_han:" + number(row, "sla_id");
                notificationType = "SLA_QUA_HAN";
            } else if (warningPercent > 0 && managerId != null
                && !now.isBefore(deadline.minusNanos((long)(number(row, "thoi_han_phut") * warningPercent / 100.0 * 60_000_000_000L)))) {
                body = "SLA " + type + " của hồ sơ " + caseNumber + " sắp quá hạn.";
                title = "SLA sắp quá hạn"; key = "sla_sap_qua_han:" + number(row, "sla_id");
                notificationType = "SLA_SAP_QUA_HAN";
            }
            if (detectedAt != null || key != null) {
                save(row, status, time(row.get("thoi_diem_bat_dau")), endAt,
                    number(row, "thoi_gian_tam_dung_phut"), nullableTime(row.get("thoi_diem_tam_dung")),
                    detectedAt, body, managerId, key, title, body, notificationType, now);
            }
        }
    }

    private List<Map<String, Object>> rows(Long caseId) {
        return repository.findByCaseId(caseId);
    }

    private Map<String, Object> findSla(Long caseId, String type) {
        return rows(caseId).stream().filter(row -> type.equals(text(row, "loai_sla"))).findFirst().orElse(null);
    }

    private void save(Map<String, Object> row, String status, OffsetDateTime startAt, OffsetDateTime endAt,
                      long paused, OffsetDateTime pauseAt, OffsetDateTime detectedAt, String violationNote,
                      Long receiver, String key, String title, String body, String type, OffsetDateTime now) {
        repository.save(number(row, "sla_id"), text(row, "trang_thai"), status, startAt, endAt,
            paused, pauseAt, detectedAt, violationNote, receiver, key, title, body, type, now);
    }

    private static OffsetDateTime deadline(Map<String, Object> row, long paused) {
        return time(row.get("thoi_diem_bat_dau")).plusMinutes(number(row, "thoi_han_phut") + paused);
    }
    private static long pausedMinutes(OffsetDateTime start, OffsetDateTime end) {
        java.time.Duration duration = java.time.Duration.between(start, end);
        long seconds = Math.max(0, duration.getSeconds() + (duration.getNano() > 0 ? 1 : 0));
        return (seconds + 59) / 60;
    }
    private static String text(Map<String, Object> row, String key) { Object value=row.get(key); return value == null ? "" : value.toString(); }
    private static long number(Map<String, Object> row, String key) { return row.get(key) instanceof Number n ? n.longValue() : 0L; }
    private static Long nullableNumber(Object value) { return value instanceof Number n ? n.longValue() : null; }
    private static double decimal(Object value) { return value instanceof Number n ? n.doubleValue() : 20.0; }
    private static OffsetDateTime time(Object value) {
        if (value instanceof OffsetDateTime t) return t;
        if (value instanceof java.sql.Timestamp t) return t.toInstant().atZone(ZONE).toOffsetDateTime();
        throw new IllegalStateException("Thiếu dữ liệu thời gian SLA: " + value);
    }
    private static OffsetDateTime nullableTime(Object value) { return value == null ? null : time(value); }
}
