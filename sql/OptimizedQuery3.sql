WITH rental_counts AS (
    SELECT
        customer_id,
        COUNT(*) AS rental_count
    FROM rental
    GROUP BY customer_id
),
average_count AS (
    SELECT AVG(rental_count) AS avg_rental_count
    FROM rental_counts
)
SELECT
    c.customer_id,
    c.first_name,
    c.last_name,
    rc.rental_count
FROM rental_counts AS rc
JOIN customer AS c
    ON c.customer_id = rc.customer_id
CROSS JOIN average_count AS ac
WHERE rc.rental_count > ac.avg_rental_count
ORDER BY rc.rental_count DESC;
