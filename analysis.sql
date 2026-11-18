/* =====================================================================
   Olist E-Commerce Analysis
   ===================================================================== */


/* ---------------------------------------------------------------------
   PART 0: GET TO KNOW THE DATA
   --------------------------------------------------------------------- */

-- How many orders, and what statuses exist?
SELECT order_status, COUNT(*) AS n_orders
FROM orders
GROUP BY order_status
ORDER BY n_orders DESC;

-- What date range does the data cover?
SELECT MIN(order_purchase_timestamp) AS first_order,
       MAX(order_purchase_timestamp) AS last_order
FROM orders;

-- Missing values: delivered orders with no delivery date?
SELECT COUNT(*) AS delivered_but_no_date
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NULL;
-- customer_id is unique PER ORDER; customer_unique_id identifies the actual person
SELECT COUNT(DISTINCT customer_id)        AS customer_ids,
       COUNT(DISTINCT customer_unique_id) AS actual_people
FROM customers;

/* ---------------------------------------------------------------------
   Q1: How have monthly revenue and order volume changed over time?
   --------------------------------------------------------------------- */

WITH monthly AS (
    SELECT
        strftime('%Y-%m', o.order_purchase_timestamp) AS month,
        COUNT(DISTINCT o.order_id)                    AS orders,
        ROUND(SUM(oi.price), 2)                       AS revenue   -- product price only, excludes freight
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'   -- exclude sparse start-up months
      AND o.order_purchase_timestamp <  '2018-09-01'   -- exclude incomplete final months
    GROUP BY month
)
SELECT
    month,
    orders,
    revenue,
    -- Window function: compare each month to the previous one
    ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month))
          / LAG(revenue) OVER (ORDER BY month), 1) AS revenue_mom_pct
FROM monthly
ORDER BY month;

/* Findings for Q1:
   - Overall trend: Revenue grew ~6.5x during 2017, from R$112K (Jan) to
  R$726K (Dec), then leveled off around R$900K/month through Aug 2018.
   - Biggest month: November 2017 at R$988K.
   - Anomaly: Nov 2017 revenue jumped 52% over October, driven by Black
  Friday (Nov 24): 1,176 orders vs. a typical October day of ~149,
  roughly 7.9x normal volume.
*/


/* ---------------------------------------------------------------------
   Q2: Which product categories bring in the most revenue?
   --------------------------------------------------------------------- */


SELECT
    COALESCE(ct.product_category_name_english, p.product_category_name, 'unknown') AS category,
    ROUND(SUM(oi.price), 2) AS revenue,
    ROUND(100.0 * SUM(oi.price) / SUM(SUM(oi.price)) OVER (), 1) AS pct_of_total
FROM order_items oi
JOIN orders o   ON o.order_id = oi.order_id
JOIN products p ON p.product_id = oi.product_id
LEFT JOIN category_translation ct ON ct.product_category_name = p.product_category_name
WHERE o.order_status = 'delivered'
GROUP BY category
ORDER BY revenue DESC
LIMIT 10;

/* Findings for Q2:
   - Top 3 categories: health_beauty (R$1.23M), watches_gifts (R$1.17M),
  bed_bath_table (R$1.02M), close to each other, with no single dominant category.
   - Concentration: the top 10 categories = 62% of revenue.
*/


/* ---------------------------------------------------------------------
   Q3: Does late delivery hurt review scores?
   --------------------------------------------------------------------- */

WITH delivered AS (
    SELECT o.order_id,
           julianday(date(o.order_delivered_customer_date))
         - julianday(date(o.order_estimated_delivery_date)) AS days_late
    FROM orders o
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
)
SELECT
    CASE
        WHEN d.days_late <= 0 THEN 'on time'
        WHEN d.days_late <= 3 THEN '1-3 days late'
        WHEN d.days_late <= 7 THEN '4-7 days late'
        ELSE '8+ days late'
    END AS delivery_status,
    ROUND(AVG(r.review_score), 2) AS review_score_avg,
    COUNT(DISTINCT r.order_id)    AS sample_size
FROM delivered d
JOIN order_reviews r ON r.order_id = d.order_id
GROUP BY delivery_status
ORDER BY MIN(d.days_late);


/* Findings for Q3:
   - Avg score, on time: 4.29 stars (n = 89,443)
   - Avg score, late: scores fall as delays grow: 3.29 (1–3 days), 2.10 (4–7),
  1.70 (8+ days). Even a short delay costs a full star.
   - Difference: ~2.0 stars lower (−47%). The gap widens with delay:
  −1.0 (1–3 days), −2.2 (4–7), −2.6 (8+).
   - 8+ day delays are the largest late group (2,781 orders, 44% of late).
*/


/* ---------------------------------------------------------------------
   Q4: Where are customers, and where is delivery slowest?
   --------------------------------------------------------------------- */

WITH delivered AS (
    SELECT o.order_id,
           o.customer_id,
           julianday(o.order_delivered_customer_date)
         - julianday(o.order_purchase_timestamp)              AS delivery_days,
           julianday(date(o.order_delivered_customer_date))
         - julianday(date(o.order_estimated_delivery_date))   AS days_late
    FROM orders o
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
)
SELECT
    c.customer_state,
    COUNT(DISTINCT c.customer_unique_id)                                AS n_customers,
    ROUND(AVG(d.delivery_days), 1)                                      AS avg_delivery_days,
    SUM(CASE WHEN d.days_late > 0 THEN 1 ELSE 0 END)                    AS n_late_orders,
    ROUND(100.0 * SUM(CASE WHEN d.days_late > 0 THEN 1 ELSE 0 END)
          / COUNT(*), 1)                                                AS pct_late
FROM delivered d
JOIN customers c ON c.customer_id = d.customer_id
GROUP BY c.customer_state
ORDER BY avg_delivery_days DESC;


/* Findings for Q4:
   - Most customers: SP (42%), then RJ (13%) and MG (12%); top 3 = ~2/3 of customers
   - Fastest: SP at 8.8 days avg
   - Slowest: RR, AP, AM at 26–29 days, but AP and AM have some of the lowest
  late rates (3.0%, 2.8%) because estimates account for the distance.
  Small samples (n = 40–140), so treat with caution
   - Highest late rate: AL (21%), MA (17%), SE (15%), Northeast states
   where delivery estimates are too optimistic
   - Biggest opportunity: RJ, the 2nd-largest market with a 12% late rate
   (~3x SP), roughly 1,400 late orders
*/


/* ---------------------------------------------------------------------
   Q5: What share of customers buy more than once?
   --------------------------------------------------------------------- */

WITH orders_per_customer AS (
	SELECT 
	customers.customer_unique_id AS customer,
	COUNT(orders.order_id) AS order_count
	FROM customers
	INNER JOIN orders
		ON customers.customer_id = orders.customer_id
	WHERE orders.order_status = 'delivered'
	GROUP BY customers.customer_unique_id
)

SELECT
    COUNT(*)                                            AS total_customers,
    SUM(CASE WHEN order_count = 1  THEN 1 ELSE 0 END)   AS single_order,
    SUM(CASE WHEN order_count >= 2 THEN 1 ELSE 0 END)   AS multiple_order,
    ROUND(100.0 * SUM(CASE WHEN order_count >= 2 THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                AS repeat_rate_pct
FROM orders_per_customer;


/* Findings for Q5:
  - Repeat purchase rate: 3% (2801 of 93358 customers ordered 2+ times)
  - What this suggests: Olist depends almost entirely on new customers.
  Even a small increase in repeat buyers would be meaningful revenue,
  so retention (post-purchase emails, first-reorder discounts) is a
  big untapped opportunity.
*/