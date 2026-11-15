package haumai.core.util;

import org.springframework.stereotype.Component;

import java.util.Map;

@Component("nhanTrangThai")
public class TrangThaiLabel {
    private static final Map<String, String> NHAN = Map.ofEntries(
        Map.entry("MOI", "Mới"),
        Map.entry("DANG_XAC_MINH", "Đang xác minh"),
        Map.entry("CHO_KHACH_BO_SUNG", "Chờ khách bổ sung"),
        Map.entry("CHO_PHAN_CONG", "Chờ phân công"),
        Map.entry("DANG_SUA_CHUA", "Đang sửa chữa"),
        Map.entry("DA_SUA_XONG", "Đã sửa xong"),
        Map.entry("TU_CHOI", "Từ chối"),
        Map.entry("DA_DONG", "Đã đóng"),
        Map.entry("CHO_CSKH_XU_LY", "Chờ chăm sóc khách hàng xử lý"),
        Map.entry("CHO_LINH_KIEN", "Chờ linh kiện"),
        Map.entry("DANG_DEM", "Đang tính thời hạn"),
        Map.entry("TAM_DUNG", "Tạm dừng"),
        Map.entry("DA_QUA_HAN", "Đã quá hạn"),
        Map.entry("DAT_SLA", "Đạt thời hạn cam kết"),
        Map.entry("KHONG_DAT_SLA", "Không đạt thời hạn cam kết"),
        Map.entry("SAP_DEN_HAN", "Sắp đến hạn"),
        Map.entry("QUA_HAN", "Quá hạn"),
        Map.entry("DANG_CON_HAN", "Còn trong hạn"),
        Map.entry("CON_HAN", "Còn hạn bảo hành"),
        Map.entry("HET_HAN", "Hết hạn bảo hành"),
        Map.entry("CHUA_XAC_DINH", "Chưa xác định"),
        Map.entry("CHO_GUI", "Chờ gửi"),
        Map.entry("DA_GUI", "Đã gửi"),
        Map.entry("THAT_BAI", "Gửi thất bại"),
        Map.entry("DANG_XU_LY", "Đang xử lý"),
        Map.entry("DA_LIEN_KET_HO_SO", "Đã liên kết hồ sơ"),
        Map.entry("CHUA_CO_HO_SO", "Chưa có hồ sơ")
    );

    public String hienThi(Object giaTri) {
        if (giaTri == null) return "";
        String ma = giaTri instanceof Enum<?> e ? e.name() : giaTri.toString();
        return NHAN.getOrDefault(ma, ma.replace('_', ' ').toLowerCase(java.util.Locale.forLanguageTag("vi")));
    }
}
