-- Replace placeholder labels that were visible in the product and customer lists.
UPDATE public.san_pham
SET serial = CASE serial
        WHEN 'SN-DEMO-001' THEN 'HM-RO-2026-007'
        WHEN 'SN-DEMO-002' THEN 'HM-HC-2025-008'
        WHEN 'SN-DEMO-003' THEN 'HM-RO-2024-009'
        ELSE serial
    END,
    ten_san_pham = CASE serial
        WHEN 'SN-DEMO-001' THEN 'Máy lọc nước RO HauMai AquaCare 7'
        WHEN 'SN-DEMO-002' THEN 'Máy lọc nước nóng lạnh HauMai H2 Plus'
        WHEN 'SN-DEMO-003' THEN 'Máy lọc nước RO HauMai Pure 9'
        ELSE ten_san_pham
    END
WHERE serial IN ('SN-DEMO-001', 'SN-DEMO-002', 'SN-DEMO-003');

UPDATE public.khach_hang
SET ho_ten = CASE lower(btrim(ho_ten))
        WHEN 'demo' THEN 'Nguyễn Minh Anh'
        WHEN 'khach demo' THEN 'Trần Gia Bảo'
        ELSE regexp_replace(ho_ten, '(?i)demo', '', 'g')
    END,
    email = CASE
        WHEN email ILIKE '%demo%' THEN 'khachhang-' || id || '@example.local'
        ELSE email
    END
WHERE ho_ten ILIKE '%demo%' OR email ILIKE '%demo%';
