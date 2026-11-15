CREATE OR REPLACE VIEW public.v_tin_nhan_cuoc_tro_chuyen AS
SELECT m.id, m.cuoc_tro_chuyen_id, m.ho_so_id, m.ma_tin_goc,
       m.huong_tin, m.noi_dung, m.trang_thai_gui, m.tao_luc, m.gui_luc,
       kg.ma_kenh
FROM public.tin_nhan_cuoc_tro_chuyen m
JOIN public.cuoc_tro_chuyen c ON c.id = m.cuoc_tro_chuyen_id
JOIN public.kenh_goc kg ON kg.id = c.kenh_id;

ALTER VIEW public.v_tin_nhan_cuoc_tro_chuyen OWNER TO hau_mai_owner;
REVOKE ALL ON TABLE public.v_tin_nhan_cuoc_tro_chuyen FROM PUBLIC;
GRANT SELECT ON TABLE public.v_tin_nhan_cuoc_tro_chuyen TO hau_mai_app;
