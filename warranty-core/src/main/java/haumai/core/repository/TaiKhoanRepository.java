package haumai.core.repository;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class TaiKhoanRepository {
    private final JdbcTemplate jdbc;
    public TaiKhoanRepository(JdbcTemplate jdbc) { this.jdbc = jdbc; }
    public AccountCredentials findByUsername(String username) {
        return jdbc.query("SELECT ten_dang_nhap, mat_khau_bam, vai_tro, dang_hoat_dong FROM tai_khoan WHERE ten_dang_nhap = ?", rs -> {
            if (!rs.next()) return null;
            return new AccountCredentials(rs.getString("ten_dang_nhap"), rs.getString("mat_khau_bam"),
                rs.getString("vai_tro"), rs.getBoolean("dang_hoat_dong"));
        }, username);
    }
    public record AccountCredentials(String username, String passwordHash, String role, boolean active) {}
}
