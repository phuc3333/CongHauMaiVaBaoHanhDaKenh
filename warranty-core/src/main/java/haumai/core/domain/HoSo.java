package haumai.core.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.Version;

import java.time.Instant;

@Entity
@Table(name = "ho_so")
public class HoSo {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "ma_ho_so", nullable = false, unique = true, length = 30)
    private String maHoSo;

    @Column(name = "khach_hang_id", nullable = false)
    private Long khachHangId;

    @Column(name = "serial", length = 100)
    private String serial;

    @Column(name = "kenh_goc_id", nullable = false)
    private Long kenhGocId;

    @Column(name = "mo_ta_loi", nullable = false, columnDefinition = "text")
    private String moTaLoi;

    @Column(name = "ngay_tiep_nhan", nullable = false)
    private Instant ngayTiepNhan;

    @Enumerated(EnumType.STRING)
    @Column(name = "trang_thai", nullable = false, length = 40)
    private TrangThaiHoSo trangThai;

    @Column(name = "ket_qua_xac_minh", columnDefinition = "text")
    private String ketQuaXacMinh;

    @Column(name = "ly_do_tu_choi", columnDefinition = "text")
    private String lyDoTuChoi;

    @Column(name = "ngoai_bao_hanh", nullable = false)
    private boolean ngoaiBaoHanh;

    @Column(name = "ket_luan_xu_ly", columnDefinition = "text")
    private String ketLuanXuLy;

    @Column(name = "bat_dau_cho_khach_luc")
    private Instant batDauChoKhachLuc;

    @Column(name = "ngay_dong")
    private Instant ngayDong;

    @Version
    @Column(name = "version", nullable = false)
    private Long version;

    @Column(name = "tao_luc", nullable = false)
    private Instant taoLuc;

    protected HoSo() {
    }

    public Long getId() { return id; }
    public String getMaHoSo() { return maHoSo; }
    public Long getKhachHangId() { return khachHangId; }
    public String getSerial() { return serial; }
    public Long getKenhGocId() { return kenhGocId; }
    public String getMoTaLoi() { return moTaLoi; }
    public Instant getNgayTiepNhan() { return ngayTiepNhan; }
    public TrangThaiHoSo getTrangThai() { return trangThai; }
    public String getKetQuaXacMinh() { return ketQuaXacMinh; }
    public String getLyDoTuChoi() { return lyDoTuChoi; }
    public boolean isNgoaiBaoHanh() { return ngoaiBaoHanh; }
    public String getKetLuanXuLy() { return ketLuanXuLy; }
    public Instant getBatDauChoKhachLuc() { return batDauChoKhachLuc; }
    public Instant getNgayDong() { return ngayDong; }
    public Long getVersion() { return version; }
    public Instant getTaoLuc() { return taoLuc; }
}
