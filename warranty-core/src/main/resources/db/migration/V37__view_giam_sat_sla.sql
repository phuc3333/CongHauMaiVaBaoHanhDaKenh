-- Keep dashboard-only customer and assignment details behind an owner view.
CREATE OR REPLACE VIEW public.v_sla_dashboard AS
SELECT
    s.ho_so_id,
    hs.ma_ho_so,
    hs.trang_thai AS trang_thai_ho_so,
    hs.mo_ta_loi,
    kh.ho_ten AS ten_khach_hang,
    s.loai_sla,
    s.nhan_trang_thai,
    s.thoi_gian_hien_thi,
    s.den_han_luc,
    s.phut_con_lai,
    ktv.ho_ten AS ky_thuat_vien
FROM public.v_sla_ho_so s
JOIN public.ho_so hs ON hs.id = s.ho_so_id
JOIN public.khach_hang kh ON kh.id = hs.khach_hang_id
LEFT JOIN LATERAL (
    SELECT nv.ho_ten
    FROM public.phan_cong pc
    JOIN public.nhan_vien nv ON nv.id = pc.ky_thuat_vien_id
    WHERE pc.ho_so_id = hs.id AND pc.dang_hieu_luc = TRUE
    ORDER BY pc.ngay_phan_cong DESC, pc.id DESC
    LIMIT 1
) ktv ON TRUE;

ALTER VIEW public.v_sla_dashboard OWNER TO hau_mai_owner;
REVOKE ALL ON TABLE public.v_sla_dashboard FROM PUBLIC;
GRANT SELECT ON TABLE public.v_sla_dashboard TO hau_mai_app;
