# Sakila expansion

The complete runnable script is `sql/expand-sakila.sql` (revision V3). Run the whole file in a
fresh MySQL connection against the existing official Sakila database, with
application writes paused. It uses `DELIMITER`, supported by the mysql client
and MySQL Workbench. Do not re-run `sakila-schema.sql`: that official installer
drops and recreates the database.

## Schema inspection

The supplied `original-database/sakila-db/sakila-schema.sql` and `sakila-data.sql` were
inspected before writing the generator. The expansion script also prints the
live table definitions, constraints and triggers before its generation call.

Important details addressed by the script:

- `address.location` is a required geometry column with a spatial index.
  Staff and customers reuse existing residential addresses as shared households;
  store addresses are excluded. No new geometry or address rows are needed.
- The official data installer creates `customer_create_date`, `rental_date`, and `payment_date`
  triggers that assign `NOW()`. The script preserves them, sets MySQL's session
  clock for each historical insert, and checks that the inserted date matches.
  It restores the real clock afterward, including on SQL errors.
- Rental uniqueness is `(rental_date, inventory_id, customer_id)`. Chronological
  generation and inventory availability prevent duplicate combinations.
- Original IDs are not assumed to be gap-free. New primary keys use the existing
  auto-increment columns; generated references use actual IDs.
- All PK, FK, UNIQUE and NOT NULL constraints stay enabled. No business table,
  original record, column type, index or trigger is altered, dropped or replaced.
- `payment.payment_id` remains `SMALLINT UNSIGNED`, whose maximum value is 65,535.
  The previous working draft's widening to `INT` has been removed. A payment
  for every one of 150,000 rentals cannot fit this original schema. V3 adds a
  deterministic sample of 40,000 payments, for 56,044 total, and checks available
  auto-increment capacity before any data writes. It rejects an already-widened
  payment column instead of modifying it again.

## Records added

| Table | Original rows | Added rows | Final rows |
|---|---:|---:|---:|
| store | 2 | 0 | 2 |
| staff | 2 | 8 | 10 |
| customer | 599 | 901 | 1,500 |
| rental | 16,044 | 133,956 | 150,000 |
| payment | 16,044 | 40,000 | 56,044 |
| address | 603 | 0 | 603 |

These counts describe a fresh original Sakila baseline. When backfilling a V1
dataset, only 40,000 payments are inserted: its existing staff, customers,
rentals and 1,512 addresses are retained unchanged.

Each store ends with exactly five staff members. Each new staff member and
customer gets a valid existing household address. Store managers remain the original staff members.
The script reuses existing cities, countries, inventory and films. The only
persistent helper object it adds is `expand_synthetic_v3`, a stored procedure.
Working tables are temporary and are dropped after successful generation.

Synthetic payments span both original and new customers and all ten staff.
Each sampled rental has one base-rate checkout payment. Its customer and staff
IDs come directly from that rental, its amount comes from the rented film's
`rental_rate`, and its payment date equals the checkout date. This prevents
independently sampled foreign keys from creating inconsistent relationships.
Existing rentals already have original payments and do not receive extras.

The 40,000 rentals are selected by a stable SHA-256 ordering of the entire
synthetic rental population, not by the earliest dates, lowest customer IDs,
or original staff. Underlying customer, staff and time distributions are
therefore represented in the payment sample. Other synthetic rentals have no
payment record in this sampled dataset; this does not model them as unpaid.
Payment-based reports cover the original history plus a sample of the new
period, not complete revenue for all 150,000 rentals. No aggregated payment is
misleadingly assigned to one rental to work around the ID capacity.

## Full relationship review

| Generated relationship | Selection and consistency rule |
|---|---|
| Staff → store | Reuse the two existing stores; reach five staff per store. |
| Staff/customer → address | Reuse all eligible addresses already present; create none. |
| Customer → store | Reuse the two existing stores, with the existing 55/45 preference. |
| Rental → customer | Build the pool after customer generation; include all active original and new customers. Inactive customers are intentionally excluded. |
| Rental → staff | Build the pool after staff generation; include original and new staff in the renting store. |
| Rental → inventory → film | Reuse available copies and their films; exclude copies still out on original rentals. No new inventory or films are needed. |
| Payment → rental | Sample synthetic rentals across the full generated period. Already-paid original rentals need no duplicate payment. |
| Payment → customer/staff | Copy the selected rental's actual references; both original/new customer and staff cohorts must be represented. |
| Store → manager | Preserve existing managers; adding staff does not require replacing managers. |

The original-customer name snapshot is only a first/last-name vocabulary, not a
foreign-key pool. Keeping it stable avoids making names depend on insertion
order. No additional cities, countries, films, inventory or store records are
needed. V1 addresses are retained during backfill rather than deleted.

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

The script accepts official baseline counts of 2 stores, 2 staff, 599 customers
and 16,044 rentals, or V1's expanded counts with the expected synthetic markers
and period. Both paths require exactly the original 16,044 payments and no
synthetic payments. An expanded V1 dataset receives payments only. Unknown,
partially paid or already-completed datasets are rejected. The retained
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
creation dates for synthetic events. Payment checks include all three FKs,
customer/staff/date/amount consistency, staff/inventory store agreement,
duplicate payments per synthetic rental, 40,000 sampled payments, 93,956 rentals
outside that sample, payments per staff member, and original/new parent cohorts.

MySQL documents the session clock in its
[system-variable reference](https://dev.mysql.com/doc/refman/8.0/en/server-system-variables.html#sysvar_timestamp).
The modeling of staff serving their own store's inventory is consistent with
[Sakila's documented assumption](https://dev.mysql.com/doc/sakila/en/sakila-known-issues.html).

## Historical V1 test results

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

These historical results describe V1, which created addresses and no payments.
Current revision output is saved in `results/sakila-expansion-v3-verification.txt`.

## V3 constraint-preserving test results

Tested with MySQL 8.0.46 in a separate disposable instance loaded from the
supplied official files. The existing `.mysql-test` instance was not used or
modified for this review.

- Fresh generation reached 2 stores, 10 staff, 1,500 customers, 150,000 rentals,
  56,044 payments and 603 addresses.
- All 47,268 original base-table rows remained present and byte-for-byte equal
  in SQL data dumps.
- Table definitions, indexes, foreign keys, column types, views and triggers
  matched before/after schema dumps, ignoring only advancing auto-increment
  counters. `payment_id` remained `SMALLINT UNSIGNED`.
- Synthetic payments: 40,000, with 23,398 referencing new customers and 16,602
  referencing original customers; 27,389 referencing new staff and 12,611
  referencing original staff. Every staff member received synthetic payments.
- The sample spans `2006-03-01 10:15:32`–`2008-02-29 21:49:38`; amounts range
  from 0.99 to 4.99, totaling 118,950.00. These are sampled base charges.
- All requested rental integrity checks, payment FK checks, payment/rental
  consistency checks, and duplicate synthetic payment checks returned zero.
- A repeated call was rejected before adding data.
- A deliberately exhausted payment ID counter in the test instance was
  rejected before any payment insert; the original 16,044 payments remained.
- Simulating an already-expanded dataset with only original payments, then
  running the payment-only branch, produced a full data dump identical to the
  fresh-generation result. No staff, customer, rental or address was added or
  changed during that backfill.
- Repeating the full file stopped at the existing V3 procedure. Payment counts
  stayed at 56,044 and the payment column type stayed `smallint unsigned`.
