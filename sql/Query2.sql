SELECT
    s.staff_id,
    s.first_name,
    s.last_name,
    -- c.active,
    COUNT(*) AS rentals_processed,
    COUNT(DISTINCT c.customer_id) AS unique_active_customers
FROM rental r
JOIN customer c
    ON c.customer_id = r.customer_id
JOIN staff s
    ON s.staff_id = r.staff_id
WHERE c.active = 1
GROUP BY
    s.staff_id,
    s.first_name,
    s.last_name
ORDER BY s.staff_id;
