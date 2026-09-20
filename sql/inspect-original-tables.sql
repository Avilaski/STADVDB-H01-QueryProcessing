USE sakila;

SELECT COUNT(*) AS rental_count
FROM rental;

SELECT COUNT(*) AS customer_count
FROM customer;

SELECT COUNT(*) AS staff_count
FROM staff;

DESCRIBE rental;
DESCRIBE customer;
DESCRIBE staff;

SHOW CREATE TABLE rental;
SHOW CREATE TABLE customer;
SHOW CREATE TABLE staff;

SELECT *
FROM rental
LIMIT 20;

SELECT *
FROM customer
LIMIT 20;

SELECT *
FROM staff;
