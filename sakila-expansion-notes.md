# Sakila expansion

The complete runnable script is `expand-sakila.sql`. Run the whole file in a
fresh MySQL connection against the existing official Sakila database, with
application writes paused. It uses `DELIMITER`, supported by the mysql client
and MySQL Workbench. Do not re-run `sakila-schema.sql`: that official installer
drops and recreates the database.

## Schema inspection

The supplied `sakila-db/sakila-schema.sql` and `sakila-db/sakila-data.sql` were
inspected before writing the generator. The expansion script also prints the
live table definitions, constraints and triggers before its generation call.

Important details addressed by the script:

- `address.location` is a required geometry column with a spatial index.
  New addresses copy valid geometry and city/district/postal details from an
  existing locality. These coordinates are locality proxies, not geocoded
  synthetic street addresses. Phone numbers and emails are synthetic fixtures.
- The official data installer creates `customer_create_date` and `rental_date`
  triggers that assign `NOW()`. The script preserves them, sets MySQL's session
  clock for each historical insert, and checks that the inserted date matches.
  It restores the real clock afterward, including on SQL errors.
- Rental uniqueness is `(rental_date, inventory_id, customer_id)`. Chronological
  generation and inventory availability prevent duplicate combinations.
- Original IDs are not assumed to be gap-free. New primary keys use the existing
  auto-increment columns; generated references use actual IDs.
- All PK, FK, UNIQUE and NOT NULL constraints stay enabled. No business table,
  original record, index or trigger is dropped or replaced.

## Records added

| Table | Original rows | Added rows | Final rows |
|---|---:|---:|---:|
| store | 2 | 0 | 2 |
| staff | 2 | 8 | 10 |
| customer | 599 | 901 | 1,500 |
| rental | 16,044 | 133,956 | 150,000 |
| address | 603 | 909 | 1,512 |

Each store ends with exactly five staff members. Each new staff member and
customer gets a new address. Store managers remain the original staff members.
The script reuses existing cities, countries, inventory and films. The only
persistent helper object it adds is `expand_synthetic_v1`, a stored procedure.
Working tables are temporary and are dropped after successful generation.

Payments are not generated. Original payments remain intact, so revenue reports
and joins that require payments cover only the original payment history.

## Dates and distributions

New rentals span **March 1, 2006 through February 29, 2008**, a 731-day observation
period. The original rental history is retained, so the combined dataset starts
in May 2005. New customers are created during February 15–28, 2006, before the
synthetic rental period. Existing historical gaps and anomalies are preserved.

The parameters are plausible modeling assumptions, not empirical estimates of
an actual video store's behavior:

- **Customer frequency:** among active customers, approximately 10% are frequent,
  20% regular and 70% occasional renters. These groups receive approximately
  48%, 24% and 28% of new rentals. Hash-based ordering assigns tiers independently
  of customer IDs; a customer keeps the same tier throughout the period. About
  2.5% of new customers are inactive and receive no rentals.
- **Staff workload:** staff ordered by ID within each store receive approximately
  32%, 25%, 20%, 15% and 8% of that store's new rentals. Original staff retain
  their historical workloads as well.
- **Store choice:** about 55% of new customers belong to the lower-ID store;
  the rest belong to the other store. Each rental has an 8% probability of a
  visit to the customer's other store. Staff and inventory always belong to
  the same store for generated events.
- **Weekly activity:** Monday–Sunday weights are 0.75, 0.70, 0.80, 0.95, 1.45,
  1.65 and 1.20, producing Friday/Saturday peaks.
- **Seasonality:** June–August activity is weighted 20% higher, December 35%
  higher. A gradual growth factor increases 20% over the two years, with
  deterministic daily fluctuations of approximately ±15%.
- **Time of day:** rentals occur from 10:00 to 22:00, with approximately 60%
  between 17:00 and 22:00. Weighted calendar intervals allocate the exact total
  count, so daily totals vary without relying on a random stopping condition.
- **Film popularity:** a stable subset of approximately 20% of film IDs has
  three times the selection weight, subject to physical copy availability.
- **Returns:** approximately 15% after one day, 25% after two days, 50% on the
  film's configured due day, and 10% three days late: durations of 1–10 days
  for official Sakila films. Copies have a two-hour turnaround before reuse.
- **Outstanding rentals:** planned returns on or after March 1, 2008 are stored
  as NULL, representing checkouts still outstanding at the observation cutoff.
  Original NULL returns are preserved, and those copies are excluded from
  synthetic rentals. NULLs are therefore concentrated near the new period's
  end rather than assigned indiscriminately across two years.

## Repeat safety and verification

The script requires official baseline counts of 2 stores, 2 staff, 599 customers
and 16,044 rentals. It refuses modified or already-expanded counts. The retained
procedure name also makes a second execution of the full file fail immediately
at procedure creation. A repeated `CALL` independently fails the baseline guard.
An advisory lock prevents concurrent calls of this generator; application writes
must still be paused because other clients need not honor that lock.

Data generation is one InnoDB transaction. An SQL exception rolls back all added
business rows, releases the advisory lock and restores session settings. A failed
run can leave the helper procedure and consume auto-increment values; reconnect
and remove only the helper procedure before retrying a corrected script.
Reproducibility assumes the same source data and auto-increment counters.

The final SQL section verifies all requested counts, foreign-key references,
return chronology, date ranges, staff workloads, customer counts and histogram,
and NULL return totals. It also checks rental uniqueness, staff/inventory store
agreement, inventory overlaps extending into the synthetic period, and customer
creation dates for synthetic events.

MySQL documents the session clock in its
[system-variable reference](https://dev.mysql.com/doc/refman/8.0/en/server-system-variables.html#sysvar_timestamp).
The modeling of staff serving their own store's inventory is consistent with
[Sakila's documented assumption](https://dev.mysql.com/doc/sakila/en/sakila-known-issues.html).

## Executed test results

Tested on an isolated MySQL Community Server 8.0.46 instance populated from the
supplied official Sakila 1.5 files. Generation and every verification query
completed successfully.

- Final counts: 2 stores, 10 staff, 1,500 customers, 150,000 rentals, 1,512 addresses.
- Five staff members in each store.
- All six requested invalid-reference/return-date checks: zero.
- Duplicate rental key groups: zero.
- Synthetic staff/inventory store mismatches, inventory overlaps extending into
  the synthetic period, and rentals before customer creation: all zero.
- Compared all 47,268 original base-table rows against a data dump after
  expansion: zero missing or changed original rows.
- Combined rental range: `2005-05-24 22:53:30`–`2008-02-29 21:59:03`.
- Synthetic rental range: `2006-03-01 10:05:10`–`2008-02-29 21:59:03`.
- NULL returns: 892 total, comprising 183 original and 709 synthetic.
- Customer rental counts: minimum 0, maximum 517; the busiest 10% of all
  customers account for 44.38% of all rentals, including original history.
- An earlier failing test confirmed that added staff and addresses rolled back
  to the original counts. The final script has no intermediate data commits.
- Repeating the full file failed with `PROCEDURE expand_synthetic_v1 already
  exists`; repeating `CALL` failed with the explicit baseline-count error.
  Counts remained unchanged after both attempts.

Full inspection and verification output is saved in
`sakila-expansion-verification.txt` alongside the script.
