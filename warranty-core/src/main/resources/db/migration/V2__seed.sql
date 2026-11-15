INSERT INTO kenh_goc (ma_kenh, ten_hien_thi, dang_bat) VALUES
    ('WEBSITE', 'Website', TRUE),
    ('EMAIL', 'Email', TRUE),
    ('FACEBOOK', 'Facebook', TRUE),
    ('ZALO', 'Zalo', TRUE);

-- Demo password for all accounts: password
INSERT INTO tai_khoan (ten_dang_nhap, mat_khau_bam, vai_tro) VALUES
    ('cskh',   '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'CSKH'),
    ('quanly', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'DIEU_PHOI_VIEN'),
    ('ktv01',  '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'KY_THUAT_VIEN'),
    ('ktv02',  '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'KY_THUAT_VIEN'),
    ('ktv03',  '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'KY_THUAT_VIEN');

INSERT INTO nhan_vien (tai_khoan_id, ho_ten, so_dien_thoai, email)
SELECT id,
       CASE ten_dang_nhap
           WHEN 'cskh' THEN 'Customer Service'
           WHEN 'quanly' THEN 'Manager'
           WHEN 'ktv01' THEN 'Technician 01'
           WHEN 'ktv02' THEN 'Technician 02'
           WHEN 'ktv03' THEN 'Technician 03'
       END,
       CASE ten_dang_nhap
           WHEN 'cskh' THEN '0900000001'
           WHEN 'quanly' THEN '0900000002'
           WHEN 'ktv01' THEN '0900000003'
           WHEN 'ktv02' THEN '0900000004'
           WHEN 'ktv03' THEN '0900000005'
       END,
       ten_dang_nhap || '@example.local'
FROM tai_khoan
WHERE ten_dang_nhap IN ('cskh', 'quanly', 'ktv01', 'ktv02', 'ktv03');

INSERT INTO san_pham (serial, ten_san_pham, ngay_mua, thoi_han_bao_hanh_thang, ngay_het_han_bao_hanh) VALUES
    ('SN-DEMO-001', 'Demo Water Filter A', current_date - 180, 24, current_date + 545),
    ('SN-DEMO-002', 'Demo Water Filter B', current_date - 700, 24, current_date + 30),
    ('SN-DEMO-003', 'Demo Water Filter C', current_date - 900, 12, current_date - 535);

INSERT INTO cau_hinh (ma_cau_hinh, gia_tri, mo_ta) VALUES
    ('sla_tiep_nhan_phut', '30', 'Intake SLA duration in minutes'),
    ('sla_xu_ly_phut', '4320', 'Processing SLA duration in minutes'),
    ('canh_bao_phan_tram', '20', 'Warning threshold percentage'),
    ('toi_da_ho_so_ky_thuat_vien', '5', 'Maximum active cases per technician'),
    ('so_ngay_cho_khach', '7', 'Days to wait for customer information'),
    ('chu_ky_quet_sla_giay', '30', 'SLA scan interval in seconds');