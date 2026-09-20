WITH actor_film_sales as (
    SELECT fa.actor_id, SUM(p.amount) AS sales
    FROM payment p
    JOIN rental r
    ON r.rental_id = p.rental_id
    JOIN inventory i
    ON i.inventory_id = r.inventory_id
    JOIN film_actor fa
    ON fa.film_id = i.film_id
    GROUP BY fa.actor_id
)
SELECT CONCAT(a.first_name, ' ', a.last_name) AS actor_name, s.sales AS actor_total_sales
FROM actor a
JOIN actor_film_sales s
ON s.actor_id = a.actor_id
WHERE s.sales > (SELECT AVG(sales) FROM actor_film_sales)
ORDER BY actor_total_sales DESC;
