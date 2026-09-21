WITH customer_rental_counts AS (
    SELECT
        c.customer_id,
        c.first_name,
        c.last_name,
        COUNT(r.rental_id) AS rental_count
    FROM customer AS c
    JOIN rental AS r
        ON c.customer_id = r.customer_id
    GROUP BY
        c.customer_id,
        c.first_name,
        c.last_name
)
SELECT
    customer_id,
    first_name,
    last_name,
    rental_count
FROM customer_rental_counts
WHERE rental_count > (
    SELECT AVG(rental_count)
    FROM customer_rental_counts
)
ORDER BY rental_count DESC;
WITH customer_rental_counts AS (
    SELECT
        c.customer_id,
        c.first_name,
        c.last_name,
        COUNT(r.rental_id) AS rental_count
    FROM customer AS c
    JOIN rental AS r
        ON c.customer_id = r.customer_id
    GROUP BY
        c.customer_id,
        c.first_name,
        c.last_name
)
SELECT
    customer_id,
    first_name,
    last_name,
    rental_count
FROM customer_rental_counts
WHERE rental_count > (
    SELECT AVG(rental_count)
    FROM customer_rental_counts
)
ORDER BY rental_count DESC;
