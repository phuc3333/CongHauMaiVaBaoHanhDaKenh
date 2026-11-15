-- Close intake SLAs left running by the previous database-driven workflow.
-- Use the first recorded verification time when available; for cases created
-- directly in verification, intake ends at the received timestamp.
WITH intake_end AS (
    SELECT s.id AS sla_id,
           COALESCE(
               (SELECT MIN(l.tao_luc)
                FROM public.lich_su_xu_ly l
                WHERE l.ho_so_id = h.id AND l.trang_thai_sang = 'DANG_XAC_MINH'),
               h.ngay_tiep_nhan
           ) AS ended_at,
           s.thoi_diem_bat_dau +
               ((s.thoi_han_phut::BIGINT + s.thoi_gian_tam_dung_phut) * INTERVAL '1 minute') AS deadline
    FROM public.sla s
    JOIN public.ho_so h ON h.id = s.ho_so_id
    WHERE s.loai_sla = 'TIEP_NHAN'
      AND s.trang_thai = 'DANG_DEM'
      AND h.trang_thai <> 'MOI'
)
UPDATE public.sla s
SET thoi_diem_ket_thuc = e.ended_at,
    trang_thai = CASE WHEN e.ended_at <= e.deadline THEN 'DAT_SLA' ELSE 'KHONG_DAT_SLA' END
FROM intake_end e
WHERE s.id = e.sla_id;
