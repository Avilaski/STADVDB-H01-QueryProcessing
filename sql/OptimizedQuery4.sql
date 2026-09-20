WITH film_revenue AS (
    SELECT fc.category_id,
           fc.film_id,
           SUM(p.amount) AS revenue
    FROM film_category fc
    JOIN inventory i ON i.film_id      = fc.film_id
    JOIN rental    r ON r.inventory_id = i.inventory_id
    JOIN payment   p ON p.rental_id    = r.rental_id
    GROUP BY fc.category_id, fc.film_id
),
with_category_avg AS (
    SELECT fr.category_id,
           fr.film_id,
           fr.revenue,
           AVG(fr.revenue) OVER (PARTITION BY fr.category_id) AS category_avg_revenue
    FROM film_revenue fr
)
SELECT c.name              AS category,
       f.title             AS film_title,
       ROUND(w.revenue, 2) AS film_revenue
FROM with_category_avg w
JOIN category c ON c.category_id = w.category_id
JOIN film     f ON f.film_id     = w.film_id
WHERE w.revenue > w.category_avg_revenue
ORDER BY c.name, film_revenue DESC;
