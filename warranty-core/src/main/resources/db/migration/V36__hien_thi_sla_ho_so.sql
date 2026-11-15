-- Expose only the presentation fields needed by the staff SLA indicators.
CREATE OR REPLACE VIEW public.v_sla_ho_so AS
WITH han AS (
    SELECT
        s.id AS sla_id,
        s.ho_so_id,
        s.loai_sla,
        s.thoi_han_phut,
        s.trang_thai,
        s.thoi_diem_bat_dau + (
            s.thoi_han_phut::BIGINT
            + s.thoi_gian_tam_dung_phut
            + CASE
                WHEN s.trang_thai = 'TAM_DUNG' AND s.thoi_diem_tam_dung IS NOT NULL
                    THEN GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (now() - s.thoi_diem_tam_dung)) / 60)::BIGINT)
                ELSE 0
              END
        ) * INTERVAL '1 minute' AS thoi_diem_den_han
    FROM public.sla s
), con_lai AS (
    SELECT h.*,
           CEIL(EXTRACT(EPOCH FROM (h.thoi_diem_den_han - now())) / 60)::BIGINT AS phut_con_lai,
           COALESCE((SELECT gia_tri::NUMERIC FROM public.cau_hinh WHERE ma_cau_hinh = 'canh_bao_phan_tram'), 20) AS nguong_canh_bao
    FROM han h
)
SELECT
    sla_id,
    ho_so_id,
    loai_sla,
    trang_thai,
    phut_con_lai,
    TO_CHAR(thoi_diem_den_han AT TIME ZONE 'Asia/Ho_Chi_Minh', 'DD/MM/YYYY HH24:MI') AS den_han_luc,
    CASE
        WHEN trang_thai = 'TAM_DUNG' THEN 'TAM_DUNG'
        WHEN trang_thai = 'DAT_SLA' THEN 'DAT_SLA'
        WHEN trang_thai = 'KHONG_DAT_SLA' THEN 'KHONG_DAT_SLA'
        WHEN trang_thai = 'DA_QUA_HAN' OR phut_con_lai <= 0 THEN 'QUA_HAN'
        WHEN phut_con_lai <= CEIL(thoi_han_phut * nguong_canh_bao / 100) THEN 'SAP_DEN_HAN'
        ELSE 'DANG_CON_HAN'
    END AS nhan_trang_thai,
    CASE
        WHEN trang_thai = 'TAM_DUNG' THEN 'Đang tạm dừng'
        WHEN trang_thai = 'DAT_SLA' THEN 'Hoàn tất đúng hạn'
        WHEN trang_thai = 'KHONG_DAT_SLA' THEN 'Hoàn tất trễ hạn'
        WHEN trang_thai = 'DA_QUA_HAN' OR phut_con_lai <= 0
            THEN 'Quá hạn ' || CEIL(ABS(phut_con_lai) / 60.0)::INTEGER || ' giờ'
        WHEN phut_con_lai >= 1440 THEN 'Còn ' || FLOOR(phut_con_lai / 1440.0)::INTEGER || ' ngày'
        WHEN phut_con_lai >= 60 THEN 'Còn ' || FLOOR(phut_con_lai / 60.0)::INTEGER || ' giờ'
        ELSE 'Còn ' || phut_con_lai::INTEGER || ' phút'
    END AS thoi_gian_hien_thi
FROM con_lai;

ALTER VIEW public.v_sla_ho_so OWNER TO hau_mai_owner;
REVOKE ALL ON TABLE public.v_sla_ho_so FROM PUBLIC;
GRANT SELECT ON TABLE public.v_sla_ho_so TO hau_mai_app;
