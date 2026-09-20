SELECT c.name  AS category,
       f.title AS film_title,
       (SELECT ROUND(SUM(p.amount), 2)
          FROM inventory i
          JOIN rental  r ON r.inventory_id = i.inventory_id
          JOIN payment p ON p.rental_id    = r.rental_id
         WHERE i.film_id = f.film_id)        AS film_revenue
FROM film f
JOIN film_category fc ON fc.film_id    = f.film_id
JOIN category      c  ON c.category_id = fc.category_id
WHERE (SELECT SUM(p.amount)
         FROM inventory i
         JOIN rental  r ON r.inventory_id = i.inventory_id
         JOIN payment p ON p.rental_id    = r.rental_id
        WHERE i.film_id = f.film_id)
      >
      (SELECT SUM(p2.amount) / COUNT(DISTINCT fc2.film_id)
         FROM film_category fc2
         JOIN inventory i2 ON i2.film_id      = fc2.film_id
         JOIN rental    r2 ON r2.inventory_id = i2.inventory_id
         JOIN payment   p2 ON p2.rental_id    = r2.rental_id
        WHERE fc2.category_id = fc.category_id)
ORDER BY c.name, film_revenue DESC;
