-- Các điều kiện phân công/tiếp nhận/hoàn tất được kiểm tra trong Service.
-- Các procedure dưới đây chỉ thực hiện ghi dữ liệu nguyên tử sau khi Service đã kiểm tra.

CREATE PROCEDURE public.sp_luu_phan_cong_da_kiem_tra(
    IN p_ho_so_id BIGINT, IN p_ky_thuat_vien_id BIGINT, IN p_dieu_phoi_vien_id BIGINT,
    IN p_ly_do TEXT, IN p_now TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_ho_so_ma VARCHAR(30); v_phan_cong_id BIGINT;
BEGIN
    SELECT ma_ho_so INTO v_ho_so_ma FROM public.ho_so WHERE id = p_ho_so_id;
    UPDATE public.phan_cong
    SET dang_hieu_luc = FALSE, ngay_ket_thuc = p_now, ly_do_thay_doi = p_ly_do
    WHERE ho_so_id = p_ho_so_id AND dang_hieu_luc = TRUE;
    INSERT INTO public.phan_cong(ho_so_id, ky_thuat_vien_id, dieu_phoi_vien_id,
        ngay_phan_cong, ly_do_thay_doi, dang_hieu_luc)
    VALUES(p_ho_so_id, p_ky_thuat_vien_id, p_dieu_phoi_vien_id, p_now, p_ly_do, TRUE)
    RETURNING id INTO v_phan_cong_id;
    INSERT INTO public.tien_do_sua_chua(phan_cong_id, trang_thai, ghi_chu, tao_luc)
    VALUES(v_phan_cong_id, 'DA_NHAN_THIET_BI', 'Khởi tạo tiến độ cho lần phân công mới', p_now);
    INSERT INTO public.thong_bao(ho_so_id, nhan_vien_nhan_id, khoa_chong_trung,
        tieu_de, noi_dung, loai_thong_bao, tao_luc)
    VALUES(p_ho_so_id, p_ky_thuat_vien_id, 'phan-cong:' || v_phan_cong_id,
        'Hồ sơ mới được phân công', 'Bạn được giao xử lý hồ sơ ' || v_ho_so_ma || '.', 'PHAN_CONG', p_now)
    ON CONFLICT(khoa_chong_trung) DO NOTHING;
END;
$$;

CREATE PROCEDURE public.sp_luu_ktv_tiep_nhan(
    IN p_ho_so_id BIGINT, IN p_phan_cong_id BIGINT, IN p_ky_thuat_vien_id BIGINT, IN p_now TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
    INSERT INTO public.tien_do_sua_chua(phan_cong_id, trang_thai, ghi_chu, tao_luc)
    VALUES(p_phan_cong_id, 'DANG_SUA_CHUA', 'Kỹ thuật viên đã tiếp nhận hồ sơ', p_now);
    CALL public.sp_chuyen_trang_thai(p_ho_so_id, 'DANG_SUA_CHUA', 'NHAN_VIEN',
        p_ky_thuat_vien_id, 'Kỹ thuật viên tiếp nhận sửa chữa', p_now);
END;
$$;

CREATE PROCEDURE public.sp_luu_ktv_hoan_tat(
    IN p_ho_so_id BIGINT, IN p_phan_cong_id BIGINT, IN p_ky_thuat_vien_id BIGINT,
    IN p_ket_luan TEXT, IN p_now TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
    INSERT INTO public.tien_do_sua_chua(phan_cong_id, trang_thai, ghi_chu, tao_luc)
    VALUES(p_phan_cong_id, 'DA_SUA_XONG', p_ket_luan, p_now);
    UPDATE public.ho_so SET ket_luan_xu_ly = p_ket_luan WHERE id = p_ho_so_id;
    CALL public.sp_chuyen_trang_thai(p_ho_so_id, 'DA_SUA_XONG', 'NHAN_VIEN',
        p_ky_thuat_vien_id, p_ket_luan, p_now);
END;
$$;

ALTER PROCEDURE public.sp_luu_phan_cong_da_kiem_tra(BIGINT, BIGINT, BIGINT, TEXT, TIMESTAMPTZ) OWNER TO hau_mai_owner;
ALTER PROCEDURE public.sp_luu_ktv_tiep_nhan(BIGINT, BIGINT, BIGINT, TIMESTAMPTZ) OWNER TO hau_mai_owner;
ALTER PROCEDURE public.sp_luu_ktv_hoan_tat(BIGINT, BIGINT, BIGINT, TEXT, TIMESTAMPTZ) OWNER TO hau_mai_owner;
REVOKE EXECUTE ON PROCEDURE public.sp_luu_phan_cong_da_kiem_tra(BIGINT, BIGINT, BIGINT, TEXT, TIMESTAMPTZ) FROM PUBLIC;
REVOKE EXECUTE ON PROCEDURE public.sp_luu_ktv_tiep_nhan(BIGINT, BIGINT, BIGINT, TIMESTAMPTZ) FROM PUBLIC;
REVOKE EXECUTE ON PROCEDURE public.sp_luu_ktv_hoan_tat(BIGINT, BIGINT, BIGINT, TEXT, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE public.sp_luu_phan_cong_da_kiem_tra(BIGINT, BIGINT, BIGINT, TEXT, TIMESTAMPTZ) TO hau_mai_app;
GRANT EXECUTE ON PROCEDURE public.sp_luu_ktv_tiep_nhan(BIGINT, BIGINT, BIGINT, TIMESTAMPTZ) TO hau_mai_app;
GRANT EXECUTE ON PROCEDURE public.sp_luu_ktv_hoan_tat(BIGINT, BIGINT, BIGINT, TEXT, TIMESTAMPTZ) TO hau_mai_app;
