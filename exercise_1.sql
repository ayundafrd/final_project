-- PROJECT: End-to-End SQL Business Analysis – Tokopaedi 
-- TOOLS: PostgreSQL

-- ===== Exploratory Data Analysis =====
-- 1. Laporan total sales per bulan tahun 2024
SELECT
    TO_CHAR(transaction_date, 'Month') AS bulan,
    SUM(total_paid) AS total_sales
FROM
    transaction_detail
WHERE
    transaction_date BETWEEN '2024-01-01' AND '2025-01-01'
GROUP BY
    TO_CHAR(transaction_date, 'Month'),
    EXTRACT(MONTH FROM transaction_date)
ORDER BY
    EXTRACT(MONTH FROM transaction_date);

-- 2.  tampilkan volume (quantity) terjual per kategori setiap tahun dari 2020 s.d. 2024
SELECT
    p.category,
    SUM(CASE WHEN EXTRACT(YEAR FROM o.order_date) = 2020 THEN o.quantity ELSE 0 END) AS qty_2020,
    SUM(CASE WHEN EXTRACT(YEAR FROM o.order_date) = 2021 THEN o.quantity ELSE 0 END) AS qty_2021,
    SUM(CASE WHEN EXTRACT(YEAR FROM o.order_date) = 2022 THEN o.quantity ELSE 0 END) AS qty_2022,
    SUM(CASE WHEN EXTRACT(YEAR FROM o.order_date) = 2023 THEN o.quantity ELSE 0 END) AS qty_2023,
    SUM(CASE WHEN EXTRACT(YEAR FROM o.order_date) = 2024 THEN o.quantity ELSE 0 END) AS qty_2024
FROM
    order_detail o
JOIN
    product_detail p
    ON o.sku_id = p.sku_id
WHERE
    o.is_valid = 1
    AND EXTRACT(YEAR FROM o.order_date) BETWEEN 2020 AND 2024
GROUP BY
    p.category
ORDER BY
    p.category;

-- 3. Analisis performa channel (web, app, offline) di 2024: 
-- 3.1 Total orders (distinct) dan revenue(after_discount) per bulan
WITH order_revenue AS (
    SELECT
        channel_type,
        EXTRACT(MONTH FROM order_date) AS month_num,
        TO_CHAR(order_date, 'Month') AS bulan,
        EXTRACT(YEAR FROM order_date) AS tahun,
        COUNT(DISTINCT order_id) AS total_order,
        SUM(after_discount) AS total_revenue
    FROM
        order_detail
    WHERE
        is_valid = 1
        AND EXTRACT(YEAR FROM order_date) = 2024
    GROUP BY
        channel_type,
        EXTRACT(MONTH FROM order_date),
        TO_CHAR(order_date, 'Month'),
        EXTRACT(YEAR FROM order_date)
)
SELECT
    bulan,
    SUM(CASE WHEN channel_type = 'App Store' THEN total_order ELSE 0 END) AS total_order_appstore,
    SUM(CASE WHEN channel_type = 'App Store' THEN total_revenue ELSE 0 END) AS revenue_appstore,
    SUM(CASE WHEN channel_type = 'Offline Store' THEN total_order ELSE 0 END) AS total_order_offstore,
    SUM(CASE WHEN channel_type = 'Offline Store' THEN total_revenue ELSE 0 END) AS revenue_offstore,
    SUM(CASE WHEN channel_type = 'Play Store' THEN total_order ELSE 0 END) AS total_order_playstore,
    SUM(CASE WHEN channel_type = 'Play Store' THEN total_revenue ELSE 0 END) AS revenue_playstore,
    SUM(CASE WHEN channel_type = 'Website' THEN total_order ELSE 0 END) AS total_order_website,
    SUM(CASE WHEN channel_type = 'Website' THEN total_revenue ELSE 0 END) AS revenue_website
FROM
    order_revenue
GROUP BY
    month_num,
    bulan
ORDER BY
    month_num;

-- 3.2 Hitung MoM growth revenue per bulan vs 2023 dalam bulan yang sama
WITH order_revenue AS (
    SELECT
        channel_type,
        EXTRACT(MONTH FROM order_date) AS month_num,
        TO_CHAR(order_date, 'Month') AS bulan,
        EXTRACT(YEAR FROM order_date) AS tahun,
        COUNT(DISTINCT order_id) AS total_order,
        SUM(after_discount) AS total_revenue
    FROM
        order_detail
    WHERE
        is_valid = 1
        AND EXTRACT(YEAR FROM order_date) IN (2023, 2024)
    GROUP BY
        channel_type,
        EXTRACT(MONTH FROM order_date),
        TO_CHAR(order_date, 'Month'),
        EXTRACT(YEAR FROM order_date)
)
SELECT
    bulan,
    channel_type,
    SUM(CASE WHEN tahun = 2023 THEN total_revenue ELSE 0 END) AS revenue_2023,
    SUM(CASE WHEN tahun = 2024 THEN total_revenue ELSE 0 END) AS revenue_2024,
    ROUND(
        (
            (SUM(CASE WHEN tahun = 2024 THEN total_revenue ELSE 0 END) - 
             SUM(CASE WHEN tahun = 2023 THEN total_revenue ELSE 0 END))::NUMERIC
            / NULLIF(SUM(CASE WHEN tahun = 2023 THEN total_revenue ELSE 0 END), 0)
            * 100
        ), 2
    ) AS growth_vs_2023
FROM
    order_revenue
GROUP BY
    month_num,
    bulan,
    channel_type
ORDER BY
    month_num;

-- 4.  laporan kinerja funnel untuk event “Organic” di funnel_detail periode 1 Jan 31 Des 2024:  
-- 4.1 Total jumlah event organic per channel_source. 
-- 4.2 Total unique order_id (“converted”) dari event organic. 
-- 4.3 Conversion rate = total_orders ÷ total_events × 100%.
SELECT
    channel_source,
    COUNT(event) AS total_organic_events, ----- 4.1
    COUNT(DISTINCT CASE WHEN order_id IS NOT NULL 
        THEN order_id END) AS total_converted_orders, ----- 4.2
    ROUND(
        COUNT(DISTINCT CASE WHEN order_id IS NOT NULL 
            THEN order_id END)::NUMERIC 
        / COUNT(event) 
        * 100, 2
    ) AS conversion_rate_pct ----- 4.3
FROM
    funnel_detail
WHERE
    event = 'Organic'
    AND funnel_date BETWEEN '2024-01-01' AND '2024-12-31'
GROUP BY
    channel_source
ORDER BY
    channel_source;

-- 5. buatkan laporan per bulan (Hanya hitung pelanggan yang sudah melakukan minimal satu pembelian) selama 2024 untuk: 
-- 5.1 Jumlah pelanggan baru (distinct customer_id) yang registrasi per registration_channel. 
-- 5.2 Rata-rata selisih hari antara registration_date dan tanggal transaksi pertama (order_date). 
WITH first_order AS (
    SELECT
        customer_id,
        MIN(order_date::DATE) AS first_order_date
    FROM
        order_detail
    WHERE
        is_valid = 1
    GROUP BY
        customer_id
),
customer_with_first_order AS (
    SELECT
        c.customer_id,
        c.registration_date,
        c.registration_channel,
        f.first_order_date,
        DATE_TRUNC('month', c.registration_date)::DATE AS registration_month
    FROM
        customer_detail c
    JOIN
        first_order f
        ON c.customer_id = f.customer_id
    WHERE
        c.registration_date BETWEEN '2024-01-01' AND '2024-12-31'
)
SELECT
    TO_CHAR(registration_month, 'FMMonth YYYY') AS reg_month,
    registration_channel,
    COUNT(DISTINCT customer_id) AS new_customers, -----5.1
    ROUND(
        AVG(first_order_date - registration_date)
    ) AS avg_selisih_hari -----5.2
FROM
    customer_with_first_order
GROUP BY
    registration_month,
    registration_channel
ORDER BY
    registration_month,

    registration_channel;
