-- Expose only customer contact fields needed by staff case workspaces.
CREATE OR REPLACE VIEW public.v_ho_so_khach_hang AS
SELECT
    hs.id AS ho_so_id,
    kh.ho_ten AS ten_khach_hang,
    kh.so_dien_thoai
FROM public.ho_so hs
JOIN public.khach_hang kh ON kh.id = hs.khach_hang_id;

ALTER VIEW public.v_ho_so_khach_hang OWNER TO hau_mai_owner;
REVOKE ALL ON TABLE public.v_ho_so_khach_hang FROM PUBLIC;
GRANT SELECT ON TABLE public.v_ho_so_khach_hang TO hau_mai_app;
