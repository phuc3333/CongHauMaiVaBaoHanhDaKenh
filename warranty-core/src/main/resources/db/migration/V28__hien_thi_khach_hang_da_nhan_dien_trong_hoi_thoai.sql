CREATE OR REPLACE VIEW public.v_cuoc_tro_chuyen AS
SELECT c.id, kg.ma_kenh, c.ma_nguoi_dung_kenh, c.khach_hang_id, c.ho_so_id,
       c.cap_nhat_luc,
       (SELECT m.noi_dung FROM public.tin_nhan_cuoc_tro_chuyen m
        WHERE m.cuoc_tro_chuyen_id = c.id
        ORDER BY m.tao_luc DESC, m.id DESC LIMIT 1) AS tin_moi_nhat,
       kh.ho_ten AS ten_khach_hang,
       kh.so_dien_thoai
FROM public.cuoc_tro_chuyen c
JOIN public.kenh_goc kg ON kg.id = c.kenh_id
LEFT JOIN public.khach_hang kh ON kh.id = c.khach_hang_id;

ALTER VIEW public.v_cuoc_tro_chuyen OWNER TO hau_mai_owner;
REVOKE ALL ON TABLE public.v_cuoc_tro_chuyen FROM PUBLIC;
GRANT SELECT ON TABLE public.v_cuoc_tro_chuyen TO hau_mai_app;
