-- Core đã chuyển các luồng này qua Service và procedure chỉ ghi dữ liệu.
-- Thu hồi quyền gọi trực tiếp các procedure cũ để không tạo đường vòng nghiệp vụ.
REVOKE EXECUTE ON PROCEDURE public.sp_phan_cong(BIGINT, BIGINT, BIGINT, TEXT, TIMESTAMPTZ) FROM hau_mai_app;
REVOKE EXECUTE ON PROCEDURE public.sp_dong_ho_so(BIGINT, BIGINT, TEXT, TIMESTAMPTZ) FROM hau_mai_app;
REVOKE EXECUTE ON PROCEDURE public.sp_xac_minh(BIGINT, VARCHAR, TEXT, BIGINT, TIMESTAMPTZ) FROM hau_mai_app;
REVOKE EXECUTE ON PROCEDURE public.sp_ktv_tiep_nhan_phan_cong(BIGINT, BIGINT, TIMESTAMPTZ) FROM hau_mai_app;
REVOKE EXECUTE ON PROCEDURE public.sp_hoan_tat_sua_chua(BIGINT, BIGINT, VARCHAR, TEXT, TIMESTAMPTZ) FROM hau_mai_app;
REVOKE EXECUTE ON PROCEDURE public.sp_ghi_nhan_tin_tiep_theo_kenh(VARCHAR, VARCHAR, VARCHAR, TEXT, TIMESTAMPTZ) FROM hau_mai_app;
REVOKE EXECUTE ON PROCEDURE public.sp_ghi_nhan_tin_tiep_theo_facebook(VARCHAR, VARCHAR, TEXT, TIMESTAMPTZ) FROM hau_mai_app;
