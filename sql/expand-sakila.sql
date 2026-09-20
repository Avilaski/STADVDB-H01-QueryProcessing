-- MySQL 8.0+, official Sakila. Run this WHOLE file in a fresh connection.
-- mysql CLI: do not use --force. Workbench: execute the whole SQL script.
-- Stop application writes during generation. Requires SELECT, INSERT,
-- CREATE ROUTINE, EXECUTE, CREATE TEMPORARY TABLES and session-variable access.
-- No original rows, indexes, constraints or triggers are changed.
-- The helper procedure is retained intentionally: a second CREATE fails;
-- a second CALL also fails its baseline guard before inserting any rows.
-- All data inserts commit together or roll back together. Helper DDL is
-- outside that transaction. Failed inserts may consume auto-increment IDs.
-- Reproducible from the same baseline, counters and fixed hash seeds.
-- V3: 40,000 sampled checkout payments; reuse existing addresses.
-- Also accepts the exact V1 expanded counts/markers to backfill payments only.
-- Original payment_id SMALLINT UNSIGNED is preserved (maximum 65,535).
-- Payments cover a reproducible sample, NOT every rental or complete revenue.
-- No business-table DDL is performed; all existing column types stay intact.

USE sakila;

-- Inspect the LIVE schema before generation, including data-file triggers.
SELECT VERSION() AS mysql_version;
SHOW CREATE TABLE store;
SHOW CREATE TABLE staff;
SHOW CREATE TABLE customer;
SHOW CREATE TABLE rental;
SHOW CREATE TABLE payment;
SHOW CREATE TABLE address;
SHOW CREATE TABLE inventory;
SHOW CREATE TABLE city;
SHOW CREATE TABLE country;
SHOW CREATE TABLE film;
SHOW TRIGGERS FROM sakila;
SELECT TABLE_NAME, CONSTRAINT_NAME, CONSTRAINT_TYPE
FROM information_schema.TABLE_CONSTRAINTS
WHERE CONSTRAINT_SCHEMA = 'sakila'
ORDER BY TABLE_NAME, CONSTRAINT_NAME;

DELIMITER $$
CREATE PROCEDURE sakila.expand_synthetic_v3()
SQL SECURITY INVOKER
BEGIN
    DECLARE v_lock INT DEFAULT 0;
    DECLARE v_tz VARCHAR(64) DEFAULT @@session.time_zone;
    DECLARE v_mode TEXT DEFAULT @@session.sql_mode;
    DECLARE v_stats_expiry BIGINT DEFAULT @@session.information_schema_stats_expiry;
    DECLARE v_n INT DEFAULT 0;
    DECLARE v_j INT;
    DECLARE v_store INT;
    DECLARE v_store1 INT;
    DECLARE v_store2 INT;
    DECLARE v_addr INT;
    DECLARE v_customer INT;
    DECLARE v_staff INT;
    DECLARE v_inv INT;
    DECLARE v_inv_count INT;
    DECLARE v_inv_count1 INT;
    DECLARE v_inv_count2 INT;
    DECLARE v_backfill BOOLEAN DEFAULT FALSE;
    DECLARE v_address_count INT;
    DECLARE v_payment_next BIGINT UNSIGNED;
    DECLARE v_customers INT;
    DECLARE v_frequent INT;
    DECLARE v_regular INT;
    DECLARE v_rank INT;
    DECLARE v_attempt INT;
    DECLARE v_duration INT;
    DECLARE v_weight INT;
    DECLARE v_total BIGINT;
    DECLARE v_before BIGINT;
    DECLARE v_hi BIGINT;
    DECLARE v_u DOUBLE;
    DECLARE v_pos DOUBLE;
    DECLARE v_frac DOUBLE;
    DECLARE v_day DATE;
    DECLARE v_dt DATETIME;
    DECLARE v_return DATETIME;
    DECLARE v_free DATETIME;
    DECLARE v_cutoff DATETIME DEFAULT '2008-03-01 00:00:00';
    DECLARE v_need INT;
    DECLARE v_last_id INT;
    DECLARE v_first_name VARCHAR(45);
    DECLARE v_last_name VARCHAR(45);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET SESSION timestamp = 0;
        SET SESSION time_zone = v_tz;
        SET SESSION sql_mode = v_mode;
        SET SESSION information_schema_stats_expiry = v_stats_expiry;
        IF v_lock = 1 THEN DO RELEASE_LOCK('sakila.expand_synthetic_v1'); END IF;
        RESIGNAL;
    END;

    SELECT GET_LOCK('sakila.expand_synthetic_v1', 0) INTO v_lock;
    IF COALESCE(v_lock, 0) <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Another Sakila generator is running.';
    END IF;
    IF @@session.autocommit <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Use a fresh autocommit session with no open transaction.';
    END IF;
    IF @@session.foreign_key_checks <> 1 OR @@session.unique_checks <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Enable FOREIGN_KEY_CHECKS and UNIQUE_CHECKS first.';
    END IF;
    SET SESSION time_zone = '+00:00';
    SET SESSION sql_mode = 'TRADITIONAL,ONLY_FULL_GROUP_BY';
    -- All generator revisions share the same advisory lock.
    IF (SELECT COUNT(*) FROM store)=2 AND (SELECT COUNT(*) FROM staff)=2
       AND (SELECT COUNT(*) FROM customer)=599 AND (SELECT COUNT(*) FROM rental)=16044 THEN
        SET v_backfill = FALSE;
    ELSEIF (SELECT COUNT(*) FROM store)=2 AND (SELECT COUNT(*) FROM staff)=10
       AND (SELECT COUNT(*) FROM customer)=1500 AND (SELECT COUNT(*) FROM rental)=150000
       AND (SELECT COUNT(*) FROM staff WHERE username REGEXP '^sx_v1_[1-8]$')=8
       AND (SELECT COUNT(*) FROM customer
            WHERE email REGEXP '^customer[0-9]+@example[.]invalid$')=901
       AND (SELECT COUNT(*) FROM rental
            WHERE rental_date >= '2006-03-01' AND rental_date < '2008-03-01')=133956 THEN
        SET v_backfill = TRUE;
    ELSE
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Expected official baseline or V1 expanded data; refusing a partial/unknown dataset.';
    END IF;
    IF (SELECT COUNT(*) FROM payment)<>16044
       OR EXISTS (SELECT 1 FROM payment WHERE payment_date >= '2006-03-01')
       OR EXISTS (SELECT 1 FROM payment p JOIN rental r ON r.rental_id=p.rental_id
                  WHERE r.rental_date >= '2006-03-01') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Expected original 16044 payments only; synthetic payments already exist or data was modified.';
    END IF;
    IF (SELECT COUNT(*) FROM information_schema.TABLES
        WHERE TABLE_SCHEMA = 'sakila'
          AND TABLE_NAME IN ('staff','customer','rental','payment')
          AND ENGINE = 'InnoDB') <> 4 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Destination tables must use InnoDB for rollback.';
    END IF;
    IF (SELECT COUNT(*) FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = 'sakila' AND TABLE_NAME = 'address'
          AND COLUMN_NAME = 'location' AND DATA_TYPE = 'geometry') <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Expected official MySQL 8 Sakila address.location geometry.';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.TRIGGERS
        WHERE TRIGGER_SCHEMA = 'sakila'
          AND EVENT_OBJECT_TABLE IN ('address','staff','customer','rental','payment')
          AND NOT ((TRIGGER_NAME = 'rental_date' AND EVENT_OBJECT_TABLE = 'rental'
                    AND ACTION_TIMING = 'BEFORE' AND EVENT_MANIPULATION = 'INSERT')
                OR (TRIGGER_NAME = 'customer_create_date' AND EVENT_OBJECT_TABLE = 'customer'
                    AND ACTION_TIMING = 'BEFORE' AND EVENT_MANIPULATION = 'INSERT')
                OR (TRIGGER_NAME = 'payment_date' AND EVENT_OBJECT_TABLE = 'payment'
                    AND ACTION_TIMING = 'BEFORE' AND EVENT_MANIPULATION = 'INSERT'))) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Unexpected destination-table trigger; review before generation.';
    END IF;
    IF NOT v_backfill AND (EXISTS (SELECT 1 FROM rental WHERE rental_date >= '2006-03-01'
               OR return_date >= '2006-03-01' OR return_date < rental_date)
       OR EXISTS (SELECT 1 FROM customer WHERE create_date >= '2006-03-01')) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Baseline dates incompatible with fixed synthetic period.';
    END IF;
    IF NOT v_backfill AND EXISTS (SELECT 1 FROM store s LEFT JOIN staff t ON t.store_id = s.store_id
               GROUP BY s.store_id HAVING COUNT(t.staff_id) <> 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Expected one original staff member in each store.';
    END IF;
    SELECT MIN(store_id), MAX(store_id) INTO v_store1, v_store2 FROM store;
    SET v_need = 150000 - (SELECT COUNT(*) FROM rental);
    SELECT COUNT(*) INTO v_address_count FROM address;

    -- Preserve the original type and check remaining AUTO_INCREMENT capacity.
    -- Counters can be higher than MAX(id) after a previously rolled-back run.
    IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
          WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='payment' AND COLUMN_NAME='payment_id'
            AND COLUMN_TYPE='smallint unsigned' AND IS_NULLABLE='NO'
            AND COLUMN_KEY='PRI' AND EXTRA LIKE '%auto_increment%') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Expected original SMALLINT UNSIGNED payment_id; no schema migration is performed.';
    END IF;
    IF @@session.auto_increment_increment<>1 OR @@session.auto_increment_offset<>1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Use auto_increment_increment=1 and auto_increment_offset=1.';
    END IF;
    SET SESSION information_schema_stats_expiry = 0;
    SELECT AUTO_INCREMENT INTO v_payment_next FROM information_schema.TABLES
    WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='payment';
    SET SESSION information_schema_stats_expiry = v_stats_expiry;
    IF v_payment_next IS NULL OR v_payment_next+39999>65535 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient payment ID capacity for 40000 rows; original schema left unchanged.';
    END IF;

    START TRANSACTION;
    IF NOT v_backfill THEN

    -- Reuse residential addresses as shared households. No extra addresses,
    -- cities or countries are needed; avoid assigning people store addresses.
    CREATE TEMPORARY TABLE sx_addresses (rn INT PRIMARY KEY,address_id INT NOT NULL);
    INSERT INTO sx_addresses
    SELECT ROW_NUMBER() OVER (ORDER BY a.address_id) AS rn, a.address_id FROM address a
    WHERE NOT EXISTS (SELECT 1 FROM store s WHERE s.address_id=a.address_id);
    CREATE TEMPORARY TABLE sx_names (rn INT PRIMARY KEY,first_name VARCHAR(45),last_name VARCHAR(45));
    INSERT INTO sx_names
    SELECT ROW_NUMBER() OVER (ORDER BY customer_id) AS rn, first_name, last_name FROM customer;

    -- Original names are a vocabulary, not an FK selection pool.
    -- Eight staff and 901 customers reuse valid household addresses.
    WHILE v_n < 909 DO
        SET v_n = v_n + 1;
        SET v_store = IF(v_n <= 8,
            IF(v_n <= 4, v_store1, v_store2),
            IF(MOD(CONV(SUBSTR(SHA2(CONCAT('store:',v_n),256),1,8),16,10),100) < 55,
               v_store1, v_store2));
        SET v_rank = 1 + MOD(CONV(SUBSTR(SHA2(CONCAT('household:',v_n),256),1,8),16,10),
                            (SELECT COUNT(*) FROM sx_addresses));
        SELECT address_id INTO v_addr FROM sx_addresses WHERE rn=v_rank;
        SET v_dt = TIMESTAMPADD(SECOND, MOD(v_n * 11939, 14 * 86400), '2006-02-15 00:00:00');
        SET SESSION timestamp = UNIX_TIMESTAMP(v_dt);
        IF v_n <= 8 THEN
            INSERT INTO staff(first_name,last_name,address_id,email,store_id,active,username,password)
            VALUES(ELT(v_n,'Alex','Jordan','Taylor','Morgan','Casey','Riley','Jamie','Avery'),
                   ELT(v_n,'Reyes','Chen','Patel','Garcia','Kim','Santos','Martin','Wilson'),
                   v_addr,CONCAT('staff',v_n,'@example.invalid'),v_store,1,
                   CONCAT('sx_v1_',v_n),NULL);
        ELSE
            SELECT first_name INTO v_first_name FROM sx_names WHERE rn=1+MOD(v_n*73,599);
            SELECT last_name INTO v_last_name FROM sx_names WHERE rn=1+MOD(v_n*137,599);
            INSERT INTO customer(store_id,first_name,last_name,email,address_id,active,create_date)
            VALUES(v_store,v_first_name,v_last_name,
                   CONCAT('customer',v_n-8,'@example.invalid'),v_addr,
                   IF(MOD(v_n,40)=0,0,1),v_dt);
            IF (SELECT create_date FROM customer WHERE customer_id = LAST_INSERT_ID()) <> v_dt THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Customer trigger did not honor session timestamp.';
            END IF;
        END IF;
    END WHILE;

    -- Hash order makes frequency tiers independent of original/new IDs.
    CREATE TEMPORARY TABLE sx_customers (rn INT PRIMARY KEY,customer_id INT,store_id INT);
    INSERT INTO sx_customers
    SELECT ROW_NUMBER() OVER (ORDER BY SHA2(CONCAT('rank:',customer_id),256),customer_id) AS rn,
           customer_id,store_id FROM customer WHERE active = 1;
    SELECT COUNT(*) INTO v_customers FROM sx_customers;
    SET v_frequent = FLOOR(v_customers * 0.10);
    SET v_regular = FLOOR(v_customers * 0.20);
    CREATE TEMPORARY TABLE sx_staff (store_id INT,staff_id INT,rn INT,PRIMARY KEY(store_id,rn));
    INSERT INTO sx_staff
    SELECT store_id,staff_id,ROW_NUMBER() OVER (PARTITION BY store_id ORDER BY staff_id) AS rn FROM staff;
    CREATE TEMPORARY TABLE sx_inventory (
        rn INT,inventory_id INT,store_id INT,rental_duration INT,popularity INT,
        available_at DATETIME,PRIMARY KEY(store_id,rn));
    INSERT INTO sx_inventory
    SELECT ROW_NUMBER() OVER (PARTITION BY i.store_id ORDER BY i.inventory_id) AS rn,
           i.inventory_id,i.store_id,f.rental_duration,
           IF(MOD(i.film_id,5)=0,3,1) AS popularity,
           CAST('2006-03-01 00:00:00' AS DATETIME) AS available_at
    FROM inventory i JOIN film f ON f.film_id = i.film_id
    WHERE NOT EXISTS (SELECT 1 FROM rental r
                      WHERE r.inventory_id = i.inventory_id AND r.return_date IS NULL);
    SELECT COUNT(*) INTO v_inv_count FROM sx_inventory WHERE store_id=v_store1;
    SET v_inv_count1 = v_inv_count;
    IF v_inv_count < 500 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient available inventory in first store.';
    END IF;
    SELECT COUNT(*) INTO v_inv_count FROM sx_inventory WHERE store_id=v_store2;
    SET v_inv_count2 = v_inv_count;
    IF v_inv_count < 500 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient available inventory.';
    END IF;

    -- Calendar weights: weekend/seasonal peaks, 20% growth, daily variation.
    -- Normalize weights to exactly v_need events over 731 calendar days.
    CREATE TEMPORARY TABLE sx_days(day_date DATE PRIMARY KEY, weight INT NOT NULL,
                                   lo BIGINT NOT NULL, hi BIGINT NOT NULL, KEY(hi));
    SET v_day = '2006-03-01';
    SET v_total = 0;
    WHILE v_day < DATE(v_cutoff) DO
        SET v_weight = ROUND(1000 *
            ELT(WEEKDAY(v_day)+1,0.75,0.70,0.80,0.95,1.45,1.65,1.20) *
            CASE WHEN MONTH(v_day) IN (6,7,8) THEN 1.20
                 WHEN MONTH(v_day)=12 THEN 1.35 ELSE 1.00 END *
            (1 + 0.20 * DATEDIFF(v_day,'2006-03-01') / 730) *
            (0.85 + MOD(CONV(SUBSTR(SHA2(CONCAT('day:',v_day),256),1,8),16,10),301)/1000));
        INSERT INTO sx_days VALUES(v_day,v_weight,v_total,v_total+v_weight);
        SET v_total = v_total + v_weight;
        SET v_day = v_day + INTERVAL 1 DAY;
    END WHILE;

    SET v_n = 0;
    WHILE v_n < v_need DO
        SET v_n = v_n + 1;
        SET v_pos = (v_n - 0.5) * v_total / v_need;
        SELECT day_date,lo,hi INTO v_day,v_before,v_hi
        FROM sx_days WHERE hi > v_pos ORDER BY hi LIMIT 1;
        SET v_frac = (v_pos-v_before)/(v_hi-v_before);
        -- Open 10:00-22:00, with 60% of activity during 17:00-22:00.
        SET v_dt = TIMESTAMPADD(SECOND,
            FLOOR(IF(v_frac < 0.4,36000 + v_frac/0.4*25200,
                     61200 + (v_frac-0.4)/0.6*18000)),CAST(v_day AS DATETIME));
        SET v_j = MOD(CONV(SUBSTR(SHA2(CONCAT('tier:',v_n),256),1,8),16,10),100);
        SET v_u = (CONV(SUBSTR(SHA2(CONCAT('customer:',v_n),256),1,8),16,10)+0.5)/4294967296;
        -- 10% frequent / 20% regular / 70% occasional customers receive
        -- approximately 48% / 24% / 28% of synthetic rental events.
        SET v_rank = CASE WHEN v_j<48 THEN 1+FLOOR(v_u*v_frequent)
            WHEN v_j<72 THEN v_frequent+1+FLOOR(v_u*v_regular)
            ELSE v_frequent+v_regular+1+FLOOR(v_u*(v_customers-v_frequent-v_regular)) END;
        SELECT customer_id,store_id INTO v_customer,v_store FROM sx_customers WHERE rn = v_rank;
        -- 8% cross-store visits; staff always belong to the renting store.
        IF MOD(CONV(SUBSTR(SHA2(CONCAT('visit:',v_n),256),1,8),16,10),100) < 8 THEN
            SET v_store = IF(v_store=v_store1,v_store2,v_store1);
        END IF;
        SET v_j = MOD(CONV(SUBSTR(SHA2(CONCAT('staff:',v_n),256),1,8),16,10),100);
        SET v_rank = CASE WHEN v_j<32 THEN 1 WHEN v_j<57 THEN 2
                          WHEN v_j<77 THEN 3 WHEN v_j<92 THEN 4 ELSE 5 END;
        SELECT staff_id INTO v_staff FROM sx_staff WHERE store_id=v_store AND rn=v_rank;
        SET v_inv_count = IF(v_store=v_store1,v_inv_count1,v_inv_count2);
        SET v_attempt = 0;
        inventory_choice: LOOP
            SET v_attempt = v_attempt + 1;
            IF v_attempt > 10000 THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Inventory capacity exceeded; generation rolled back.';
            END IF;
            SET v_rank = 1 + MOD(CONV(SUBSTR(SHA2(CONCAT('inv:',v_n,':',v_attempt),256),1,8),16,10),v_inv_count);
            SELECT inventory_id,rental_duration,popularity,available_at
            INTO v_inv,v_duration,v_weight,v_free
            FROM sx_inventory WHERE store_id=v_store AND rn=v_rank;
            IF v_free <= v_dt AND
               MOD(CONV(SUBSTR(SHA2(CONCAT('pop:',v_n,':',v_attempt),256),1,8),16,10),3) < v_weight THEN
                LEAVE inventory_choice;
            END IF;
        END LOOP;
        -- 15% return after 1 day, 25% after 2, 50% on the film's due day,
        -- 10% three days late. Actual durations therefore span 1-10 days.
        SET v_j = MOD(CONV(SUBSTR(SHA2(CONCAT('duration:',v_n),256),1,8),16,10),100);
        SET v_duration = CASE WHEN v_j<15 THEN 1 WHEN v_j<40 THEN 2
                              WHEN v_j<90 THEN v_duration ELSE v_duration+3 END;
        SET v_return = TIMESTAMPADD(DAY,v_duration,v_dt);
        UPDATE sx_inventory SET available_at = v_return + INTERVAL 2 HOUR
        WHERE store_id=v_store AND rn=v_rank;
        -- Official triggers set dates to NOW(); use a session clock so those
        -- triggers remain intact. Restore the real clock on success/error.
        SET SESSION timestamp = UNIX_TIMESTAMP(v_dt);
        INSERT INTO rental(rental_date,inventory_id,customer_id,return_date,staff_id)
        VALUES(v_dt,v_inv,v_customer,IF(v_return >= v_cutoff,NULL,v_return),v_staff);
        SET v_last_id = LAST_INSERT_ID();
        IF (SELECT rental_date FROM rental WHERE rental_id=v_last_id) <> v_dt THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Rental trigger did not honor session timestamp.';
        END IF;
    END WHILE;

    DROP TEMPORARY TABLE sx_addresses,sx_names,sx_customers,sx_staff,sx_inventory,sx_days;
    END IF;

    -- Original rentals already have payments. Sample the full synthetic rental
    -- population, spanning both old/new customers and all ten staff members.
    -- Hash sampling preserves workload/seasonal skew without a date/ID cutoff.
    CREATE TEMPORARY TABLE sx_payments (rental_id INT PRIMARY KEY);
    INSERT INTO sx_payments
    SELECT r.rental_id FROM rental r
    WHERE r.rental_date >= '2006-03-01' AND r.rental_date < '2008-03-01'
      AND NOT EXISTS (SELECT 1 FROM payment p WHERE p.rental_id=r.rental_id)
    ORDER BY SHA2(CONCAT('payment-sample-v3:',r.rental_id),256),r.rental_id
    LIMIT 40000;

    -- Derive each payment from its rental, never independently sample its FKs.
    -- Both original and new customers/staff are represented by these rentals.
    -- One base-rate payment at checkout for each SAMPLED rental, including
    -- still-out rentals. Other rentals have no synthetic payment in this sample;
    -- this is not evidence that they were unpaid. No late-fee rows are added.
    BEGIN
        DECLARE v_done BOOLEAN DEFAULT FALSE;
        DECLARE v_amount DECIMAL(5,2);
        DECLARE payment_cursor CURSOR FOR
            SELECT r.rental_id,r.customer_id,r.staff_id,r.rental_date,f.rental_rate
            FROM sx_payments selected JOIN rental r ON r.rental_id=selected.rental_id
            JOIN inventory i ON i.inventory_id=r.inventory_id
            JOIN film f ON f.film_id=i.film_id
            WHERE r.rental_date >= '2006-03-01' AND r.rental_date < '2008-03-01'
            ORDER BY r.rental_id;
        DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done=TRUE;
        OPEN payment_cursor;
        payment_loop: LOOP
            FETCH payment_cursor INTO v_last_id,v_customer,v_staff,v_dt,v_amount;
            IF v_done THEN LEAVE payment_loop; END IF;
            SET SESSION timestamp=UNIX_TIMESTAMP(v_dt);
            INSERT INTO payment(customer_id,staff_id,rental_id,amount,payment_date,last_update)
            VALUES(v_customer,v_staff,v_last_id,v_amount,v_dt,v_dt);
        END LOOP;
        CLOSE payment_cursor;
    END;

    IF (SELECT COUNT(*) FROM store) <> 2 OR (SELECT COUNT(*) FROM staff) <> 10
       OR (SELECT COUNT(*) FROM customer) <> 1500 OR (SELECT COUNT(*) FROM rental) <> 150000
       OR (SELECT COUNT(*) FROM payment) <> 56044
       OR (SELECT COUNT(*) FROM address) <> v_address_count
       OR EXISTS (SELECT 1 FROM rental WHERE return_date < rental_date)
       OR EXISTS (SELECT 1 FROM staff GROUP BY store_id HAVING COUNT(*) <> 5) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Final validation failed; generation rolled back.';
    END IF;
    IF EXISTS (
        SELECT selected.rental_id FROM sx_payments selected
        LEFT JOIN payment p ON p.rental_id=selected.rental_id
        GROUP BY selected.rental_id HAVING COUNT(p.payment_id)<>1
    ) OR EXISTS (
        SELECT 1 FROM payment p JOIN rental r ON r.rental_id=p.rental_id
        JOIN inventory i ON i.inventory_id=r.inventory_id JOIN film f ON f.film_id=i.film_id
        JOIN staff s ON s.staff_id=p.staff_id
        WHERE r.rental_date >= '2006-03-01' AND
          (p.customer_id<>r.customer_id OR p.staff_id<>r.staff_id
           OR s.store_id<>i.store_id OR p.payment_date<>r.rental_date OR p.amount<>f.rental_rate)
    ) OR (SELECT COUNT(DISTINCT p.staff_id) FROM payment p JOIN rental r ON r.rental_id=p.rental_id
           WHERE r.rental_date >= '2006-03-01')<>10
      OR (SELECT COUNT(DISTINCT CASE
              WHEN c.email REGEXP '^customer[0-9]+@example[.]invalid$' THEN 'new' ELSE 'original' END)
          FROM payment p JOIN rental r ON r.rental_id=p.rental_id
          JOIN customer c ON c.customer_id=p.customer_id WHERE r.rental_date >= '2006-03-01')<>2 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Payment coverage, rental consistency or trigger-date validation failed; rolled back.';
    END IF;
    DROP TEMPORARY TABLE sx_payments;
    COMMIT;
    SET SESSION timestamp = 0;
    SET SESSION time_zone = v_tz;
    SET SESSION sql_mode = v_mode;
    DO RELEASE_LOCK('sakila.expand_synthetic_v1');
END$$
DELIMITER ;

CALL sakila.expand_synthetic_v3();

-- VERIFICATION: expected 2, 10, 1500, 150000, 56044; address count unchanged.
SELECT 'store' AS table_name,COUNT(*) AS row_count FROM store
UNION ALL SELECT 'staff',COUNT(*) FROM staff
UNION ALL SELECT 'customer',COUNT(*) FROM customer
UNION ALL SELECT 'rental',COUNT(*) FROM rental
UNION ALL SELECT 'payment',COUNT(*) FROM payment
UNION ALL SELECT 'address',COUNT(*) FROM address;

-- All six invalid-reference / date counts must be zero.
SELECT 'rental_customer' AS check_name,COUNT(*) AS invalid_rows
FROM rental r LEFT JOIN customer c ON c.customer_id=r.customer_id WHERE c.customer_id IS NULL
UNION ALL SELECT 'rental_staff',COUNT(*)
FROM rental r LEFT JOIN staff s ON s.staff_id=r.staff_id WHERE s.staff_id IS NULL
UNION ALL SELECT 'rental_inventory',COUNT(*)
FROM rental r LEFT JOIN inventory i ON i.inventory_id=r.inventory_id WHERE i.inventory_id IS NULL
UNION ALL SELECT 'customer_address',COUNT(*)
FROM customer c LEFT JOIN address a ON a.address_id=c.address_id WHERE a.address_id IS NULL
UNION ALL SELECT 'staff_address',COUNT(*)
FROM staff s LEFT JOIN address a ON a.address_id=s.address_id WHERE a.address_id IS NULL
UNION ALL SELECT 'return_before_rental',COUNT(*) FROM rental WHERE return_date<rental_date;

SELECT MIN(rental_date) AS first_rental,MAX(rental_date) AS last_rental,
       MIN(return_date) AS first_return,MAX(return_date) AS last_return,
       SUM(return_date IS NULL) AS null_returns FROM rental;
SELECT 'synthetic' AS scope,MIN(rental_date) AS first_rental,MAX(rental_date) AS last_rental,
       COUNT(*) AS rentals,SUM(return_date IS NULL) AS null_returns
FROM rental WHERE rental_date >= '2006-03-01';
SELECT store_id,COUNT(*) AS staff_count FROM staff GROUP BY store_id;
SELECT s.staff_id,s.store_id,s.first_name,s.last_name,COUNT(r.rental_id) AS rentals,
       SUM(CASE WHEN r.rental_date >= '2006-03-01' THEN 1 ELSE 0 END) AS synthetic_rentals
FROM staff s LEFT JOIN rental r ON r.staff_id=s.staff_id
GROUP BY s.staff_id,s.store_id,s.first_name,s.last_name ORDER BY s.store_id,s.staff_id;

-- Every customer, including those with no rentals.
SELECT c.customer_id,c.active,COUNT(r.rental_id) AS rental_count
FROM customer c LEFT JOIN rental r ON r.customer_id=c.customer_id
GROUP BY c.customer_id,c.active ORDER BY rental_count DESC,c.customer_id;
WITH counts AS (
    SELECT c.customer_id,COUNT(r.rental_id) AS n
    FROM customer c LEFT JOIN rental r ON r.customer_id=c.customer_id GROUP BY c.customer_id
), buckets AS (
    SELECT n,CASE WHEN n=0 THEN '0' WHEN n<=25 THEN '1-25' WHEN n<=100 THEN '26-100'
                  WHEN n<=250 THEN '101-250' WHEN n<=500 THEN '251-500' ELSE '501+' END AS bucket,
           CASE WHEN n=0 THEN 0 WHEN n<=25 THEN 1 WHEN n<=100 THEN 2
                WHEN n<=250 THEN 3 WHEN n<=500 THEN 4 ELSE 5 END AS bucket_order
    FROM counts
)
SELECT bucket,COUNT(*) AS customers,SUM(n) AS rentals,ROUND(AVG(n),2) AS avg_rentals
FROM buckets GROUP BY bucket,bucket_order ORDER BY bucket_order;
WITH counts AS (
    SELECT c.customer_id,COUNT(r.rental_id) AS n
    FROM customer c LEFT JOIN rental r ON r.customer_id=c.customer_id GROUP BY c.customer_id
), ranked AS (
    SELECT n,ROW_NUMBER() OVER (ORDER BY n DESC,customer_id) AS rn FROM counts
)
SELECT MIN(n) AS minimum,MAX(n) AS maximum,ROUND(AVG(n),2) AS mean,
       ROUND(STDDEV_POP(n),2) AS stddev,
       ROUND(100*SUM(IF(rn<=150,n,0))/SUM(n),2) AS top_10_percent_share FROM ranked;

SELECT DATE_FORMAT(rental_date,'%Y-%m') AS rental_month,COUNT(*) AS rentals,
       SUM(return_date IS NULL) AS null_returns FROM rental GROUP BY rental_month ORDER BY rental_month;
SELECT DAYNAME(rental_date) AS weekday_name,COUNT(*) AS synthetic_rentals
FROM rental WHERE rental_date >= '2006-03-01'
GROUP BY WEEKDAY(rental_date),DAYNAME(rental_date) ORDER BY WEEKDAY(rental_date);

-- UNIQUE-key duplicates: no rows. Additional relationship checks: zero.
SELECT rental_date,inventory_id,customer_id,COUNT(*) AS duplicate_count
FROM rental GROUP BY rental_date,inventory_id,customer_id HAVING COUNT(*)>1;
SELECT COUNT(*) AS synthetic_staff_inventory_store_mismatch
FROM rental r JOIN staff s ON s.staff_id=r.staff_id JOIN inventory i ON i.inventory_id=r.inventory_id
WHERE r.rental_date >= '2006-03-01' AND s.store_id<>i.store_id;
WITH timeline AS (
    SELECT inventory_id,rental_date,return_date,
           LEAD(rental_date) OVER (PARTITION BY inventory_id ORDER BY rental_date,rental_id) AS next_rental
    FROM rental
)
SELECT COUNT(*) AS overlaps_into_synthetic_period FROM timeline
WHERE next_rental >= '2006-03-01' AND (return_date IS NULL OR return_date>next_rental);
-- Original Sakila has customer creation dates after some original rentals.
SELECT COUNT(*) AS synthetic_rentals_before_customer_creation
FROM rental r JOIN customer c ON c.customer_id=r.customer_id
WHERE r.rental_date >= '2006-03-01' AND r.rental_date<c.create_date;

-- PAYMENT / RELATIONSHIP AUDIT: all invalid or mismatch counts must be zero.
SHOW CREATE TABLE payment;
SELECT 'payment_customer' AS check_name,COUNT(*) AS invalid_rows
FROM payment p LEFT JOIN customer c ON c.customer_id=p.customer_id WHERE c.customer_id IS NULL
UNION ALL SELECT 'payment_staff',COUNT(*)
FROM payment p LEFT JOIN staff s ON s.staff_id=p.staff_id WHERE s.staff_id IS NULL
UNION ALL SELECT 'payment_rental',COUNT(*)
FROM payment p LEFT JOIN rental r ON r.rental_id=p.rental_id
WHERE p.rental_id IS NOT NULL AND r.rental_id IS NULL;
SELECT COUNT(*) AS synthetic_payment_mismatches
FROM payment p JOIN rental r ON r.rental_id=p.rental_id
JOIN inventory i ON i.inventory_id=r.inventory_id JOIN film f ON f.film_id=i.film_id
JOIN staff s ON s.staff_id=p.staff_id
WHERE r.rental_date >= '2006-03-01' AND
 (p.customer_id<>r.customer_id OR p.staff_id<>r.staff_id OR s.store_id<>i.store_id
  OR p.payment_date<>r.rental_date OR p.amount<>f.rental_rate);
-- No synthetic rental should have multiple payments; zero-payment rentals
-- are intentional because SMALLINT payment IDs cannot cover all 150000 rentals.
SELECT COUNT(*) AS synthetic_rentals_with_multiple_payments
FROM (
 SELECT r.rental_id FROM rental r LEFT JOIN payment p ON p.rental_id=r.rental_id
 WHERE r.rental_date >= '2006-03-01' GROUP BY r.rental_id HAVING COUNT(p.payment_id)>1
) mismatches;
SELECT COUNT(*) AS synthetic_rentals,COUNT(p.payment_id) AS sampled_payments,
       SUM(p.payment_id IS NULL) AS rentals_outside_payment_sample
FROM rental r LEFT JOIN payment p ON p.rental_id=r.rental_id
WHERE r.rental_date >= '2006-03-01';
SELECT s.staff_id,s.store_id,s.username,COUNT(p.payment_id) AS all_payments,
       SUM(CASE WHEN r.rental_date >= '2006-03-01' THEN 1 ELSE 0 END) AS synthetic_payments,
       COALESCE(SUM(p.amount),0) AS total_amount
FROM staff s LEFT JOIN payment p ON p.staff_id=s.staff_id
LEFT JOIN rental r ON r.rental_id=p.rental_id
GROUP BY s.staff_id,s.store_id,s.username ORDER BY s.store_id,s.staff_id;
-- Cohort checks demonstrate that both existing and new parent rows are used.
SELECT CASE WHEN c.email REGEXP '^customer[0-9]+@example[.]invalid$'
            THEN 'new_customer' ELSE 'original_customer' END AS customer_cohort,
       COUNT(DISTINCT c.customer_id) AS customers_with_synthetic_rentals,
       COUNT(*) AS synthetic_rentals,COUNT(p.payment_id) AS synthetic_payments
FROM rental r JOIN customer c ON c.customer_id=r.customer_id
LEFT JOIN payment p ON p.rental_id=r.rental_id
WHERE r.rental_date >= '2006-03-01' GROUP BY customer_cohort;
SELECT CASE WHEN s.username REGEXP '^sx_v1_[1-8]$'
            THEN 'new_staff' ELSE 'original_staff' END AS staff_cohort,
       COUNT(DISTINCT s.staff_id) AS staff_with_synthetic_rentals,
       COUNT(*) AS synthetic_rentals,COUNT(p.payment_id) AS synthetic_payments
FROM rental r JOIN staff s ON s.staff_id=r.staff_id
LEFT JOIN payment p ON p.rental_id=r.rental_id
WHERE r.rental_date >= '2006-03-01' GROUP BY staff_cohort;
SELECT MIN(p.payment_date) AS first_synthetic_payment,MAX(p.payment_date) AS last_synthetic_payment,
       MIN(p.amount) AS minimum_amount,MAX(p.amount) AS maximum_amount,SUM(p.amount) AS amount_total
FROM payment p JOIN rental r ON r.rental_id=p.rental_id WHERE r.rental_date >= '2006-03-01';
