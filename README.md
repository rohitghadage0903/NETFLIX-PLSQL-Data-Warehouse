#  Netflix Data Warehouse & Analytics Engine (Oracle PL/SQL)

An enterprise-grade, end-to-end Relational Data Warehouse and ETL pipeline developed in Oracle PL/SQL using the Netflix Movies & TV Shows dataset. 

This project normalizes denormalized media catalog data into a clean **Third Normal Form (3NF)** relational schema, implementing set-based tokenization, autonomous error logging, automated auditing, and cursor-based pagination.

---

##  Key Highlights & Architecture

* **Relational Schema (3NF):** Decomposes flat staging data into 5 master lookup tables and 4 associative junction tables to resolve $N:M$ relationships.
* **Set-Based String Tokenization:** Splits multi-valued comma-delimited fields (`cast`, `director`, `country`, `listed_in`) using hierarchical `CONNECT BY` queries and `REGEXP_SUBSTR`.
* **Idempotent ETL Pipeline:** Employs `MERGE INTO` (Upsert) patterns to allow continuous and repeatable batch loads without duplicate key collisions.
* **Autonomous Error Logging:** Uses `PRAGMA AUTONOMOUS_TRANSACTION` to persist ETL runtime failures and stack traces without interrupting parent transactions.
* **Business Analytics & Ref Cursors:** Provides functions for metric aggregation, talent ranking, and modern `OFFSET ... FETCH NEXT` catalog pagination.
* **Automated Audit Trail:** Tracks all row-level mutations (`INSERT`, `UPDATE`, `DELETE`) with timestamps and user details using AFTER triggers.

---

##  Project Structure

| File Name | Description |
| :--- | :--- |
| `schema.sql` | DDL scripts for Staging, 3NF Master/Junction Tables, and Audit structures. |
| `etl_package.sql` | PL/SQL package for string tokenization, data cleaning, and upserts. |
| `analytics_package.sql` | PL/SQL package containing analytical functions, ref cursors, and pagination. |
| `triggers.sql` | Row-level triggers for automatic timestamps and history tracking. |
| `test_cases.sql` | End-to-end test execution block and schema validation queries. |

---

##  Tech Stack

* **Database:** Oracle Database (19c / 21c / 23ai)
* **Tool:** Oracle SQL Developer
* **Language:** SQL, Oracle PL/SQL
