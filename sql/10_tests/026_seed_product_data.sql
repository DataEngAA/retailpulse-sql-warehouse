-- ============================================================
-- TEST 026
-- Seed Product Source Data
-- ============================================================


INSERT INTO raw.products (
    product_id,
    product_name,
    category,
    brand,
    product_status,
    source_system,
    batch_id
)
VALUES

(
    '301',
    'Laptop Pro 15',
    'Computers',
    'NovaTech',
    'ACTIVE',
    'phase2_demo',
    'product_demo_001'
),

(
    '302',
    'Wireless Mouse',
    'Accessories',
    'NovaTech',
    'ACTIVE',
    'phase2_demo',
    'product_demo_001'
),

(
    '303',
    'Mechanical Keyboard',
    'Accessories',
    'KeyWorks',
    'ACTIVE',
    'phase2_demo',
    'product_demo_001'
),

(
    '304',
    'USB-C Dock',
    'Accessories',
    'ConnectX',
    'ACTIVE',
    'phase2_demo',
    'product_demo_001'
),

(
    '305',
    'Wireless Headphones',
    'Audio',
    'SoundMax',
    'ACTIVE',
    'phase2_demo',
    'product_demo_001'
),


-- Intentionally bad product
(
    NULL,
    'Unknown Product',
    'Accessories',
    'Unknown',
    'ACTIVE',
    'phase2_demo',
    'product_demo_001'
),


-- Intentionally bad product
(
    'ABC',
    'Broken Product ID',
    'Accessories',
    'Unknown',
    'ACTIVE',
    'phase2_demo',
    'product_demo_001'
);