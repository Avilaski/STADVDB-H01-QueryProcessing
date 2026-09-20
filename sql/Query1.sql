-- EXPLAIN 
SELECT CONCAT(a.first_name, ' ', a.last_name) AS actor_name, total_sales.sales as actor_total_sales
FROM actor a
JOIN film_actor fa
ON a.actor_id = fa.actor_id
JOIN inventory i
ON fa.film_id = i.film_id
JOIN rental r
ON i.inventory_id = r.inventory_id
JOIN payment p
ON r.rental_id = p.rental_id
JOIN(
   SELECT SUM(p.amount) AS sales, fa.actor_id AS a_id
        FROM payment p
        JOIN rental r
        ON r.rental_id=p.rental_id
        JOIN inventory i
        ON i.inventory_id=r.inventory_id
        JOIN film_actor fa
        ON fa.film_id=i.film_id
        JOIN actor a
        ON fa.actor_id=a.actor_id
        GROUP BY fa.actor_id
) as total_sales
ON total_sales.a_id=a.actor_id
JOIN(
    SELECT AVG(sales) avg_sales
    FROM(
        SELECT SUM(p.amount) AS sales, fa.actor_id AS a_id
        FROM payment p
        JOIN rental r
        ON r.rental_id=p.rental_id
        JOIN inventory i
        ON i.inventory_id=r.inventory_id
        JOIN film_actor fa
        ON fa.film_id=i.film_id
        JOIN actor a
        ON fa.actor_id=a.actor_id
        GROUP BY fa.actor_id
    )as film_sales
) as film_avg

WHERE total_sales.sales > film_avg.avg_sales
GROUP BY a.actor_id, a.first_name, a.last_name
ORDER BY actor_total_sales DESC;
