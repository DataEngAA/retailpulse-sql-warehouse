INSERT INTO raw.sellers (
    seller_id,
    seller_name,
    seller_status,
    country,
    source_system,
    batch_id
)
VALUES

(
    '701',
    'TechWorld Retail',
    'ACTIVE',
    'India',
    'phase2_demo',
    'seller_demo_001'
),

(
    '702',
    'GadgetHub',
    'ACTIVE',
    'India',
    'phase2_demo',
    'seller_demo_001'
),

-- intentionally bad
(
    NULL,
    'Unknown Seller',
    'ACTIVE',
    'India',
    'phase2_demo',
    'seller_demo_001'
),

-- intentionally bad
(
    'XYZ',
    'Broken Seller ID',
    'ACTIVE',
    'India',
    'phase2_demo',
    'seller_demo_001'
);


SELECT
    raw_record_id,
    seller_id,
    seller_name,
    seller_status,
    country
FROM raw.sellers
WHERE batch_id = 'seller_demo_001'
ORDER BY raw_record_id;