INSERT INTO public.san_pham (
    serial, ten_san_pham, ngay_mua,
    thoi_han_bao_hanh_thang, ngay_het_han_bao_hanh
)
VALUES
    (
        'HM-RO-2026-004', 'Máy lọc nước RO HauMai AquaCare 10',
        current_date - 180, 24,
        (current_date - 180 + INTERVAL '24 months')::date
    ),
    (
        'HM-HC-2025-005', 'Máy lọc nước nóng lạnh HauMai H2',
        current_date - 350, 12,
        (current_date - 350 + INTERVAL '12 months')::date
    ),
    (
        'HM-RO-2024-006', 'Máy lọc nước RO HauMai Pure 8',
        current_date - 800, 12,
        (current_date - 800 + INTERVAL '12 months')::date
    )
ON CONFLICT (serial) DO NOTHING;

CREATE OR REPLACE VIEW public.v_san_pham AS
SELECT sp.serial, sp.ten_san_pham, sp.ngay_mua,
       sp.thoi_han_bao_hanh_thang, sp.ngay_het_han_bao_hanh,
       CASE
           WHEN sp.ngay_het_han_bao_hanh IS NULL THEN 'CHUA_XAC_DINH'
           WHEN sp.ngay_het_han_bao_hanh >= current_date THEN 'CON_HAN'
           ELSE 'HET_HAN'
       END AS trang_thai_bao_hanh,
       CASE
           WHEN sp.ngay_het_han_bao_hanh >= current_date
               THEN sp.ngay_het_han_bao_hanh - current_date
           ELSE 0
       END AS so_ngay_con_lai
FROM public.san_pham sp;

ALTER VIEW public.v_san_pham OWNER TO hau_mai_owner;
REVOKE ALL ON TABLE public.v_san_pham FROM PUBLIC;
GRANT SELECT ON TABLE public.v_san_pham TO hau_mai_app;
