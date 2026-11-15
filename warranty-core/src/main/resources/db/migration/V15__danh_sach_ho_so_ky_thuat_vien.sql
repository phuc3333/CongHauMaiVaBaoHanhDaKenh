CREATE OR REPLACE VIEW public.v_ho_so_ky_thuat_vien AS
SELECT
    pc.id AS phan_cong_id,
    pc.ho_so_id,
    pc.ky_thuat_vien_id,
    hs.ma_ho_so,
    hs.mo_ta_loi,
    hs.serial,
    hs.serial_khach_khai_bao,
    hs.trang_thai AS trang_thai_ho_so,
    kh.ho_ten AS ten_khach_hang,
    kh.so_dien_thoai,
    td.trang_thai AS trang_thai_tien_do,
    td.ghi_chu AS ghi_chu_tien_do,
    td.de_xuat_linh_kien,
    td.tao_luc AS cap_nhat_tien_do_luc
FROM public.phan_cong pc
JOIN public.ho_so hs ON hs.id = pc.ho_so_id
JOIN public.khach_hang kh ON kh.id = hs.khach_hang_id
LEFT JOIN LATERAL (
    SELECT
        t.trang_thai,
        t.ghi_chu,
        t.de_xuat_linh_kien,
        t.tao_luc
    FROM public.tien_do_sua_chua t
    WHERE t.phan_cong_id = pc.id
    ORDER BY t.tao_luc DESC, t.id DESC
    LIMIT 1
) td ON TRUE
WHERE pc.dang_hieu_luc = TRUE
  AND hs.trang_thai = 'DANG_SUA_CHUA';


ALTER VIEW public.v_ho_so_ky_thuat_vien
    OWNER TO hau_mai_owner;

REVOKE ALL ON TABLE public.v_ho_so_ky_thuat_vien FROM PUBLIC;

GRANT SELECT ON TABLE public.v_ho_so_ky_thuat_vien
    TO hau_mai_app;