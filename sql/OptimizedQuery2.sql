SELECT s.staff_id, s.first_name, s.last_name, x.rentals_processed, x.unique_active_customers
FROM staff s
JOIN (
SELECT r.staff_id,
COUNT(*) AS rentals_processed,
COUNT(DISTINCT r.customer_id) AS unique_active_customers
FROM rental r
JOIN customer c
ON c.customer_id = r.customer_id
AND c.active = 1
GROUP BY r.staff_id
) x
ON x.staff_id = s.staff_id
ORDER BY s.staff_id;
