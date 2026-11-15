-- Read models needed by the application service to decide where an inbound reply belongs.
CREATE OR REPLACE VIEW public.v_kenh_tich_hop AS
SELECT ma_kenh, dang_bat FROM public.kenh_goc;

CREATE OR REPLACE VIEW public.v_ho_so_mo_theo_dinh_danh_kenh AS
SELECT kg.ma_kenh, kg.dang_bat, dk.ma_nguoi_dung_kenh,
       COUNT(hs.id) FILTER (WHERE hs.trang_thai NOT IN ('DA_DONG', 'TU_CHOI'))::INTEGER AS so_ho_so_mo,
       MIN(hs.id) FILTER (WHERE hs.trang_thai NOT IN ('DA_DONG', 'TU_CHOI')) AS ho_so_id,
       MIN(hs.ma_ho_so) FILTER (WHERE hs.trang_thai NOT IN ('DA_DONG', 'TU_CHOI')) AS ma_ho_so
FROM public.kenh_goc kg
LEFT JOIN public.dinh_danh_kenh dk ON dk.kenh_id = kg.id
LEFT JOIN public.ho_so hs ON hs.khach_hang_id = dk.khach_hang_id AND hs.kenh_goc_id = kg.id
GROUP BY kg.id, dk.id;

CREATE OR REPLACE VIEW public.v_tin_nhan_kenh_goc AS
SELECT kg.ma_kenh, tn.ma_tin_goc, tn.ho_so_id, hs.ma_ho_so
FROM public.tin_nhan tn JOIN public.kenh_goc kg ON kg.id = tn.kenh_id
JOIN public.ho_so hs ON hs.id = tn.ho_so_id;

ALTER VIEW public.v_kenh_tich_hop OWNER TO hau_mai_owner;
ALTER VIEW public.v_ho_so_mo_theo_dinh_danh_kenh OWNER TO hau_mai_owner;
ALTER VIEW public.v_tin_nhan_kenh_goc OWNER TO hau_mai_owner;
REVOKE ALL ON TABLE public.v_kenh_tich_hop, public.v_ho_so_mo_theo_dinh_danh_kenh, public.v_tin_nhan_kenh_goc FROM PUBLIC;
GRANT SELECT ON TABLE public.v_kenh_tich_hop, public.v_ho_so_mo_theo_dinh_danh_kenh, public.v_tin_nhan_kenh_goc TO hau_mai_app;

-- Persistence only: routing/duplicate outcome is decided by InboundReplyService.
CREATE PROCEDURE public.sp_luu_tin_nhan_da_phan_loai(
    IN p_ma_kenh VARCHAR(30), IN p_ma_tin_goc VARCHAR(255), IN p_ho_so_id BIGINT,
    IN p_noi_dung TEXT, IN p_nhan_luc TIMESTAMPTZ, OUT p_da_ghi_nhan BOOLEAN
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_kenh_id BIGINT;
BEGIN
    SELECT id INTO v_kenh_id FROM public.kenh_goc WHERE ma_kenh = p_ma_kenh;
    INSERT INTO public.tin_nhan(ho_so_id, kenh_id, ma_tin_goc, huong_tin, noi_dung,
        nhan_vien_id, trang_thai_gui, tao_luc)
    VALUES(p_ho_so_id, v_kenh_id, p_ma_tin_goc, 'DEN', p_noi_dung,
        NULL, 'KHONG_AP_DUNG', p_nhan_luc)
    ON CONFLICT (kenh_id, ma_tin_goc) WHERE ma_tin_goc IS NOT NULL DO NOTHING;
    p_da_ghi_nhan := FOUND;
END;
$$;

ALTER PROCEDURE public.sp_luu_tin_nhan_da_phan_loai(VARCHAR, VARCHAR, BIGINT, TEXT, TIMESTAMPTZ, BOOLEAN) OWNER TO hau_mai_owner;
REVOKE EXECUTE ON PROCEDURE public.sp_luu_tin_nhan_da_phan_loai(VARCHAR, VARCHAR, BIGINT, TEXT, TIMESTAMPTZ, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE public.sp_luu_tin_nhan_da_phan_loai(VARCHAR, VARCHAR, BIGINT, TEXT, TIMESTAMPTZ, BOOLEAN) TO hau_mai_app;
