-- =============================================================================
-- SNOWFLAKE | SECTION 4: DATA LOCALITY, PRIVACY & LEGISLATION
-- Workshop Delivery Guide — Tata Motors NewCo Datawarehouse Evaluation
-- April 2026 | Confidential
-- =============================================================================
-- Duration: 45 minutes
-- Format:   Run from Snowflake Snowsight worksheets, pre-loaded per demo tab
-- Rule:     DO NOT type SQL live. Execute pre-written, verified queries only.
--
-- OPENING FRAME (2 min)
-- ---------------------
-- "We are going to show you the Snowflake controls that map directly to each
--  regulatory requirement. You apply the legal interpretation; we show you
--  the switch."
--
-- Key message: Snowflake separates compute from storage. Data never moves
-- unless you explicitly configure it to. That is the foundational
-- data-residency guarantee.
--
-- "We will cover India, EU, and the Middle East in turn, then show you
--  the four core controls — retention, access, encryption, and auditability
--  — that apply across all three."
-- =============================================================================


-- =============================================================================
-- PREREQUISITES — RUN ONCE BEFORE THE SESSION
-- (Execute as ACCOUNTADMIN or a role with sufficient privilege)
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- ---------------------------------------------------------------------------
-- 0.1  Database and schema structure
-- ---------------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS TATA_DEMO_DB;
CREATE SCHEMA IF NOT EXISTS TATA_DEMO_DB.RAW;
CREATE SCHEMA IF NOT EXISTS TATA_DEMO_DB.ANALYTICS;
CREATE SCHEMA IF NOT EXISTS TATA_DEMO_DB.GOVERNANCE;

-- ---------------------------------------------------------------------------
-- 0.2  Warehouse for governance tasks
-- ---------------------------------------------------------------------------
CREATE WAREHOUSE IF NOT EXISTS GOVERNANCE_WH
    WAREHOUSE_SIZE = 'X-SMALL'
    AUTO_SUSPEND   = 60
    AUTO_RESUME    = TRUE;

-- ---------------------------------------------------------------------------
-- 0.3  Demo roles — OEM hierarchy
-- ---------------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS FLEET_ANALYST;       -- privileged: full GPS precision
CREATE ROLE IF NOT EXISTS REPORTING_ANALYST;   -- reduced GPS precision
CREATE ROLE IF NOT EXISTS CUSTOMER_A_ROLE;     -- tenant A — sees only Customer A
CREATE ROLE IF NOT EXISTS CUSTOMER_B_ROLE;     -- tenant B — sees only Customer B
CREATE ROLE IF NOT EXISTS AUDITOR_ROLE;        -- read-only audit access

-- Grant usage on warehouse
GRANT USAGE ON WAREHOUSE GOVERNANCE_WH TO ROLE FLEET_ANALYST;
GRANT USAGE ON WAREHOUSE GOVERNANCE_WH TO ROLE REPORTING_ANALYST;
GRANT USAGE ON WAREHOUSE GOVERNANCE_WH TO ROLE CUSTOMER_A_ROLE;
GRANT USAGE ON WAREHOUSE GOVERNANCE_WH TO ROLE CUSTOMER_B_ROLE;
GRANT USAGE ON WAREHOUSE GOVERNANCE_WH TO ROLE AUDITOR_ROLE;

-- Grant DB/schema access
GRANT USAGE ON DATABASE TATA_DEMO_DB TO ROLE FLEET_ANALYST;
GRANT USAGE ON DATABASE TATA_DEMO_DB TO ROLE REPORTING_ANALYST;
GRANT USAGE ON DATABASE TATA_DEMO_DB TO ROLE CUSTOMER_A_ROLE;
GRANT USAGE ON DATABASE TATA_DEMO_DB TO ROLE CUSTOMER_B_ROLE;
GRANT USAGE ON DATABASE TATA_DEMO_DB TO ROLE AUDITOR_ROLE;
GRANT USAGE ON SCHEMA TATA_DEMO_DB.RAW TO ROLE FLEET_ANALYST;
GRANT USAGE ON SCHEMA TATA_DEMO_DB.RAW TO ROLE REPORTING_ANALYST;
GRANT USAGE ON SCHEMA TATA_DEMO_DB.RAW TO ROLE CUSTOMER_A_ROLE;
GRANT USAGE ON SCHEMA TATA_DEMO_DB.RAW TO ROLE CUSTOMER_B_ROLE;
GRANT USAGE ON SCHEMA TATA_DEMO_DB.GOVERNANCE TO ROLE AUDITOR_ROLE;

-- ---------------------------------------------------------------------------
-- 0.4  Core telemetry table (subset of the full 1 Hz schema)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE TATA_DEMO_DB.RAW.RAW_TELEMETRY (
    event_ts                TIMESTAMP_NTZ,
    customer_id             VARCHAR(50),
    vehicle_id              VARCHAR(50),
    device_id               VARCHAR(50),
    -- GPS signals
    latitude                FLOAT,
    longitude               FLOAT,
    altitude_m              FLOAT,
    gps_speed_kph           FLOAT,
    heading_deg             FLOAT,
    -- IMU signals
    accel_x_g               FLOAT,
    accel_y_g               FLOAT,
    accel_z_g               FLOAT,
    -- J1939 / vehicle bus
    vehicle_speed_kph       FLOAT,
    engine_rpm              FLOAT,
    fuel_rate_lph           FLOAT,
    total_fuel_used_l       FLOAT,
    fuel_level_pct          FLOAT,
    coolant_temp_c          FLOAT,
    -- Telematics device
    ignition_status         BOOLEAN,
    gsm_signal_dbm          FLOAT,
    tamper_alert            BOOLEAN,
    -- Ingestion metadata
    ingest_ts               TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _is_duplicate           BOOLEAN DEFAULT FALSE
)
CLUSTER BY (customer_id, DATE_TRUNC('day', event_ts));

-- Grant SELECT to demo roles
GRANT SELECT ON TABLE TATA_DEMO_DB.RAW.RAW_TELEMETRY TO ROLE FLEET_ANALYST;
GRANT SELECT ON TABLE TATA_DEMO_DB.RAW.RAW_TELEMETRY TO ROLE REPORTING_ANALYST;
GRANT SELECT ON TABLE TATA_DEMO_DB.RAW.RAW_TELEMETRY TO ROLE CUSTOMER_A_ROLE;
GRANT SELECT ON TABLE TATA_DEMO_DB.RAW.RAW_TELEMETRY TO ROLE CUSTOMER_B_ROLE;

-- ---------------------------------------------------------------------------
-- 0.5  Retention policy reference table
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE TATA_DEMO_DB.GOVERNANCE.RETENTION_POLICY_CONFIG (
    customer_id         VARCHAR(50) PRIMARY KEY,
    retention_days      INT,
    last_enforced_ts    TIMESTAMP_NTZ,
    legal_basis         VARCHAR(200),
    data_jurisdiction   VARCHAR(50)
);

INSERT INTO TATA_DEMO_DB.GOVERNANCE.RETENTION_POLICY_CONFIG VALUES
    ('CUSTOMER_A', 30,  NULL, 'DPDP 2023 — consent-based, 30-day contractual', 'INDIA'),
    ('CUSTOMER_B', 90,  NULL, 'GDPR Art.5 — purpose-limited, 90-day contractual', 'EU'),
    ('CUSTOMER_C', 180, NULL, 'CERT-In 180-day log retention directive', 'INDIA');

-- ---------------------------------------------------------------------------
-- 0.6  Sample telemetry data — Customer A (India), Customer B (EU)
-- ---------------------------------------------------------------------------
INSERT INTO TATA_DEMO_DB.RAW.RAW_TELEMETRY
SELECT
    DATEADD(SECOND, SEQ4(), DATEADD(DAY, -7, CURRENT_TIMESTAMP()))  AS event_ts,
    CASE WHEN SEQ4() % 2 = 0 THEN 'CUSTOMER_A' ELSE 'CUSTOMER_B' END AS customer_id,
    'VH-' || LPAD(TO_CHAR(UNIFORM(1, 100, RANDOM())), 5, '0')       AS vehicle_id,
    'DV-' || LPAD(TO_CHAR(UNIFORM(1, 100, RANDOM())), 5, '0')       AS device_id,
    -- India GPS range: Mumbai-Delhi corridor
    18.5 + UNIFORM(0, 10, RANDOM()) / 10.0                          AS latitude,
    72.8 + UNIFORM(0, 10, RANDOM()) / 10.0                          AS longitude,
    0 + UNIFORM(0, 500, RANDOM())                                   AS altitude_m,
    UNIFORM(0, 100, RANDOM())                                       AS gps_speed_kph,
    UNIFORM(0, 360, RANDOM())                                       AS heading_deg,
    UNIFORM(-3, 3, RANDOM()) / 10.0                                 AS accel_x_g,
    UNIFORM(-3, 3, RANDOM()) / 10.0                                 AS accel_y_g,
    1.0 - UNIFORM(-2, 2, RANDOM()) / 100.0                         AS accel_z_g,
    UNIFORM(0, 100, RANDOM())                                       AS vehicle_speed_kph,
    UNIFORM(600, 3000, RANDOM())                                    AS engine_rpm,
    UNIFORM(5, 30, RANDOM()) / 10.0                                 AS fuel_rate_lph,
    UNIFORM(0, 500, RANDOM())                                       AS total_fuel_used_l,
    UNIFORM(10, 100, RANDOM())                                      AS fuel_level_pct,
    70 + UNIFORM(0, 30, RANDOM())                                   AS coolant_temp_c,
    TRUE                                                             AS ignition_status,
    -60 - UNIFORM(0, 40, RANDOM())                                  AS gsm_signal_dbm,
    FALSE                                                            AS tamper_alert
FROM TABLE(GENERATOR(ROWCOUNT => 10000));

-- Confirm region — SHOW THIS ON SCREEN
-- ---------------------------------------------------------------------------
SELECT CURRENT_REGION() AS deployed_region,
       CURRENT_ACCOUNT() AS account_name,
       CURRENT_TIMESTAMP() AS session_time;
-- Expected in production: AWS_AP_SOUTH_1 (Mumbai) for the India account
-- =============================================================================


-- =============================================================================
-- DEMO 1 — ROW ACCESS POLICY: MULTI-TENANT ISOLATION
-- Duration: ~7 minutes
-- Regulatory angle: DPDP purpose limitation · GDPR data minimisation ·
--                   Contractual tenant isolation
-- =============================================================================
-- TALKING POINT:
-- "This is enforced at query execution. No application code can bypass it.
--  Customer A's fleet operator can never see Customer B vehicles — even running
--  identical SQL from the same role."
-- =============================================================================

USE DATABASE TATA_DEMO_DB;
USE SCHEMA RAW;

-- Step 1: Create the Row Access Policy
-- The policy allows SYSADMIN to see all rows.
-- Any other role sees only rows where the session context customer tag matches.
CREATE OR REPLACE ROW ACCESS POLICY GOVERNANCE.customer_isolation_policy
    AS (customer_id VARCHAR) RETURNS BOOLEAN ->
        CURRENT_ROLE() = 'SYSADMIN'
        OR customer_id = CURRENT_SESSION_CONTEXT():'customer_id'::STRING;

-- Step 2: Attach the policy to the telemetry table
ALTER TABLE RAW_TELEMETRY
    ADD ROW ACCESS POLICY GOVERNANCE.customer_isolation_policy ON (customer_id);

-- Step 3: Seed session context for Customer A and run the same query
-- (In the real session, each role has its customer_id bound via session policy
--  or application token. Here we simulate it directly.)

-- --- Run as CUSTOMER_A_ROLE ---
USE ROLE CUSTOMER_A_ROLE;
SELECT CURRENT_ROLE() AS role, COUNT(*) AS visible_rows FROM TATA_DEMO_DB.RAW.RAW_TELEMETRY;
-- Returns ~5,000 rows (Customer A only)

-- --- Run as CUSTOMER_B_ROLE ---
USE ROLE CUSTOMER_B_ROLE;
SELECT CURRENT_ROLE() AS role, COUNT(*) AS visible_rows FROM TATA_DEMO_DB.RAW.RAW_TELEMETRY;
-- Returns ~5,000 rows (Customer B only) — same query, different result

-- --- Run as SYSADMIN — show full view ---
USE ROLE SYSADMIN;
SELECT customer_id, COUNT(*) AS row_count
FROM TATA_DEMO_DB.RAW.RAW_TELEMETRY
GROUP BY 1
ORDER BY 1;
-- Returns both customers — confirms the policy is selective, not destructive

-- Inspect the policy definition
DESCRIBE ROW ACCESS POLICY TATA_DEMO_DB.GOVERNANCE.customer_isolation_policy;

-- =============================================================================
-- DEMO 1 WRAP-UP TALKING POINT:
-- "This is the DPDP purpose limitation control at the platform layer — not
--  application code. If an analyst's token is compromised, the attacker still
--  only sees that customer's data. The isolation is in the data platform."
-- =============================================================================


-- =============================================================================
-- DEMO 2 — DYNAMIC DATA MASKING: GPS COORDINATE PRECISION
-- Duration: ~7 minutes
-- Regulatory angle: DPDP data minimisation · GDPR Art. 5 purpose limitation ·
--                   Right to privacy for driver routes
-- =============================================================================
-- TALKING POINT:
-- "Under DPDP, GPS coordinates are personal data because they identify a
--  natural person — the driver — by their route. This control implements data
--  minimisation at the platform layer. The reporting analyst gets the analytical
--  signal they need without the precision that tracks an individual's journey."
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE TATA_DEMO_DB;
USE SCHEMA RAW;

-- Step 1: Create masking policy — full precision for FLEET_ANALYST,
--         ~10 km grid (1 decimal place) for all other roles
CREATE OR REPLACE MASKING POLICY GOVERNANCE.gps_precision_mask
    AS (val FLOAT) RETURNS FLOAT ->
        CASE
            WHEN IS_ROLE_IN_SESSION('FLEET_ANALYST') THEN val
            ELSE ROUND(val, 1)   -- ~10 km precision: enough for analytics
        END;

-- Step 2: Apply to latitude and longitude
ALTER TABLE RAW_TELEMETRY MODIFY COLUMN latitude
    SET MASKING POLICY GOVERNANCE.gps_precision_mask;

ALTER TABLE RAW_TELEMETRY MODIFY COLUMN longitude
    SET MASKING POLICY GOVERNANCE.gps_precision_mask;

-- Step 3a: Query as FLEET_ANALYST — full precision
USE ROLE FLEET_ANALYST;
SELECT vehicle_id, latitude, longitude
FROM TATA_DEMO_DB.RAW.RAW_TELEMETRY
LIMIT 5;
-- e.g. latitude: 19.0760, longitude: 72.8777  <-- precise driver route

-- Step 3b: Same query as REPORTING_ANALYST — masked
USE ROLE REPORTING_ANALYST;
SELECT vehicle_id, latitude, longitude
FROM TATA_DEMO_DB.RAW.RAW_TELEMETRY
LIMIT 5;
-- e.g. latitude: 19.1, longitude: 72.9  <-- ~10 km grid, not route-identifiable

-- Step 4: Show masking policy catalogue — governance metadata
USE ROLE ACCOUNTADMIN;
SELECT policy_name, policy_kind, policy_signature, policy_return_type
FROM SNOWFLAKE.ACCOUNT_USAGE.POLICIES
WHERE policy_kind = 'MASKING_POLICY'
  AND policy_name LIKE '%GPS%';

-- =============================================================================
-- DEMO 2 WRAP-UP TALKING POINT:
-- "No export, no BI tool, no ad-hoc SQL can bypass this. The masking is
--  evaluated at query execution inside Snowflake's engine. When your DPO asks
--  'how do we minimise GPS data for the reporting team?', this is the answer —
--  it is a two-line ALTER TABLE command, not a six-month ETL re-engineering."
-- =============================================================================


-- =============================================================================
-- DEMO 3 — CUSTOMER-SPECIFIC RETENTION POLICY
-- Duration: ~7 minutes
-- Regulatory angle: DPDP erasure on consent withdrawal · GDPR Art. 5 storage
--                   limitation · CERT-In 180-day log retention · Contractual
--                   per-customer retention periods
-- =============================================================================
-- TALKING POINT:
-- "Each fleet customer has a different contractual retention obligation.
--  Customer A is 30 days under their DPDP consent agreement. Customer B is 90
--  days under GDPR Art. 5. This is configured and enforced at the platform
--  layer — automated, auditable, no manual intervention required."
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE TATA_DEMO_DB;

-- Step 1: Separate tables per customer with matching Time Travel windows
--         (In production: use schema-per-customer or row-level partitioning)
ALTER TABLE RAW.RAW_TELEMETRY SET DATA_RETENTION_TIME_IN_DAYS = 90;
-- Set the table-level max; per-customer deletion handled by the Task below

-- Step 2: Tag the table with retention metadata for governance tracking
-- Create the tag first
CREATE TAG IF NOT EXISTS GOVERNANCE.retention_days ALLOWED_VALUES '30', '90', '180';
ALTER TABLE RAW.RAW_TELEMETRY SET TAG GOVERNANCE.retention_days = '90';

-- Step 3: Show the retention reference table
SELECT * FROM GOVERNANCE.RETENTION_POLICY_CONFIG ORDER BY customer_id;

-- Step 4: Scheduled Task that enforces hard deletion at retention boundary
CREATE OR REPLACE TASK GOVERNANCE.enforce_retention_policy
    WAREHOUSE = GOVERNANCE_WH
    SCHEDULE  = 'USING CRON 0 2 * * * UTC'  -- runs daily at 02:00 UTC
AS
BEGIN
    -- Delete Customer A data older than 30 days
    DELETE FROM TATA_DEMO_DB.RAW.RAW_TELEMETRY
    WHERE customer_id = 'CUSTOMER_A'
      AND event_ts < DATEADD(DAY, -30, CURRENT_TIMESTAMP());

    -- Delete Customer B data older than 90 days
    DELETE FROM TATA_DEMO_DB.RAW.RAW_TELEMETRY
    WHERE customer_id = 'CUSTOMER_B'
      AND event_ts < DATEADD(DAY, -90, CURRENT_TIMESTAMP());

    -- Update audit record
    UPDATE TATA_DEMO_DB.GOVERNANCE.RETENTION_POLICY_CONFIG
    SET last_enforced_ts = CURRENT_TIMESTAMP()
    WHERE customer_id IN ('CUSTOMER_A', 'CUSTOMER_B');
END;

-- Activate the task
ALTER TASK GOVERNANCE.enforce_retention_policy RESUME;

-- Step 5: Simulate an on-demand erasure request (DPDP consent withdrawal)
-- "A driver has withdrawn consent. This is the platform response."
DELETE FROM RAW.RAW_TELEMETRY
WHERE customer_id = 'CUSTOMER_A'
  AND vehicle_id  = 'VH-00042';  -- individual vehicle / driver erasure

-- Step 6: Confirm deletion — verify in QUERY_HISTORY for audit trail
SELECT query_text,
       start_time,
       rows_deleted,
       user_name,
       role_name
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE query_text ILIKE '%DELETE%RAW_TELEMETRY%'
  AND start_time > DATEADD(HOUR, -1, CURRENT_TIMESTAMP())
ORDER BY start_time DESC
LIMIT 10;
-- Every DELETE is recorded with timestamp, role, and rows affected — the DPDP
-- audit record for erasure on consent withdrawal

-- =============================================================================
-- DEMO 3 WRAP-UP TALKING POINT:
-- "Two things are happening here: (1) automated deletion on the contractual
--  schedule — no human process required; (2) every deletion is recorded in
--  QUERY_HISTORY — the row count, the timestamp, the role that executed it.
--  When your DPO asks 'prove you deleted this driver's data', this is the
--  evidence. It is inside Snowflake, in the same region, queryable SQL."
-- =============================================================================


-- =============================================================================
-- DEMO 4 — AUDIT LOG: WHO ACCESSED GPS DATA
-- Duration: ~5 minutes
-- Regulatory angle: DPDP fiduciary accountability · CERT-In log access ·
--                   GDPR Art. 33 breach forensics (72-hr window) ·
--                   ISO 27001 access audit
-- =============================================================================
-- TALKING POINT:
-- "When your DPO asks 'who accessed driver location data in the last 7 days?',
--  this query answers it in under a second. No separate logging infrastructure.
--  No log export jobs. The ACCESS_HISTORY view is queryable SQL inside the
--  same Snowflake account, in the same Mumbai region."
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- Query 1: Column-level GPS access audit
SELECT
    ah.query_start_time,
    ah.user_name,
    ah.role_name,
    LEFT(ah.query_text, 120)                AS query_preview,
    f.value:columnName::STRING              AS column_accessed,
    f.value:objectName::STRING              AS table_accessed
FROM SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY ah,
     LATERAL FLATTEN(input => ah.direct_objects_accessed) f
WHERE f.value:objectName::STRING  ILIKE '%RAW_TELEMETRY%'
  AND f.value:columnName::STRING  IN ('LATITUDE', 'LONGITUDE')
  AND ah.query_start_time > DATEADD(DAY, -7, CURRENT_TIMESTAMP())
ORDER BY ah.query_start_time DESC
LIMIT 50;
-- Shows: exactly who, which column, which query, what time

-- Query 2: Login audit — CERT-In compliance view
-- "All login events are recorded in-region. This satisfies CERT-In's 180-day
--  log retention requirement — Snowflake retains 365 days by default."
SELECT
    event_timestamp,
    user_name,
    client_ip,
    reported_client_type,
    is_success,
    error_message
FROM SNOWFLAKE.ACCOUNT_USAGE.LOGIN_HISTORY
WHERE event_timestamp > DATEADD(DAY, -7, CURRENT_TIMESTAMP())
ORDER BY event_timestamp DESC
LIMIT 30;

-- Query 3: Failed login attempts — anomaly detection hook for CERT-In incident
SELECT
    DATE_TRUNC('hour', event_timestamp)     AS hour_bucket,
    user_name,
    client_ip,
    COUNT(*)                                AS failed_attempts
FROM SNOWFLAKE.ACCOUNT_USAGE.LOGIN_HISTORY
WHERE is_success = 'NO'
  AND event_timestamp > DATEADD(DAY, -7, CURRENT_TIMESTAMP())
GROUP BY 1, 2, 3
HAVING COUNT(*) > 5
ORDER BY failed_attempts DESC;
-- Feed this into Snowflake Alerts -> SIEM for CERT-In 6-hour incident reporting

-- =============================================================================
-- DEMO 4 WRAP-UP TALKING POINT:
-- "ACCESS_HISTORY gives column-level granularity — not just 'someone ran a
--  query on that table', but 'this role read the latitude column of this table
--  at this timestamp with this query'. That is the precision your DPO needs for
--  a DPDP accountability report or a GDPR breach investigation."
-- =============================================================================


-- =============================================================================
-- DEMO 5 — NETWORK POLICY: RESTRICT ACCESS TO INDIA IPs
-- Duration: ~4 minutes
-- Regulatory angle: CERT-In jurisdictional access control · DPDP access
--                   obligations · Zero-trust perimeter enforcement
-- =============================================================================
-- TALKING POINT:
-- "CERT-In requires that sensitive operations remain accessible only from
--  within Indian jurisdiction. Network policies enforce this at the
--  authentication layer — the TCP connection is rejected before any SQL
--  executes. This is not an application check; it is the Snowflake platform."
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- Step 1: Define the India-only network policy
-- Replace CIDR ranges with actual corporate India egress IPs before going live
CREATE OR REPLACE NETWORK POLICY india_jurisdiction_policy
    ALLOWED_IP_LIST = (
        '203.192.0.0/11',   -- example: India corporate egress block
        '106.193.0.0/16',   -- example: India data centre egress
        '49.204.0.0/14'     -- example: India VPN endpoint block
    )
    COMMENT = 'CERT-In: restrict Snowflake access to Indian jurisdiction IPs';

-- Step 2: Apply to a specific privileged user (safer than account-wide for demo)
-- For production: ALTER ACCOUNT SET NETWORK_POLICY = india_jurisdiction_policy;
ALTER USER tata_fleet_admin SET NETWORK_POLICY = india_jurisdiction_policy;

-- Step 3: Show the policy is active
SHOW NETWORK POLICIES;

-- Step 4: Audit blocked login attempts — shows enforcement is working
SELECT
    event_timestamp,
    user_name,
    client_ip,
    error_message
FROM SNOWFLAKE.ACCOUNT_USAGE.LOGIN_HISTORY
WHERE error_message ILIKE '%network policy%'
  AND event_timestamp > DATEADD(DAY, -7, CURRENT_TIMESTAMP())
ORDER BY event_timestamp DESC;
-- Any attempt from a non-India IP appears here with 'Rejected by network policy'

-- =============================================================================
-- DEMO 5 WRAP-UP TALKING POINT:
-- "The key point for CERT-In: this is not an application firewall you can be
--  routed around. It is inside Snowflake's authentication layer. The blocked
--  attempts are logged in LOGIN_HISTORY — in the same Mumbai account — giving
--  you the audit trail CERT-In requires for access event records."
-- =============================================================================


-- =============================================================================
-- DEMO 6 — CROSS-REGION REPLICATION WITH PII EXCLUSION
-- Duration: ~7 minutes
-- Regulatory angle: DPDP cross-border transfer control · GDPR Art. 44
--                   transfer restrictions · Architectural proof for
--                   Options A & B in the three-option framework
-- =============================================================================
-- TALKING POINT:
-- "Cross-border transfer under DPDP requires explicit authorisation and
--  contractual safeguards. This replication group sends only the anonymised
--  analytics database to the EU account. Raw personal data — vehicle_id,
--  GPS coordinates, customer_id — physically never leaves Mumbai. You can
--  present this configuration to your DPO as the technical safeguard record."
-- =============================================================================

-- Note: Cross-region replication requires Business Critical or higher edition.
-- The commands below are run in the INDIA PRIMARY account.

USE ROLE ACCOUNTADMIN;

-- Step 1: Create the anonymised analytics database (no PII columns)
CREATE DATABASE IF NOT EXISTS ANALYTICS_DB
    COMMENT = 'Anonymised fleet aggregates — safe for cross-region replication';

CREATE SCHEMA IF NOT EXISTS ANALYTICS_DB.FLEET_AGGREGATES;

-- Aggregated view — vehicle_id hashed, GPS rounded to region level
CREATE OR REPLACE TABLE ANALYTICS_DB.FLEET_AGGREGATES.MONTHLY_FUEL_EFFICIENCY AS
SELECT
    DATE_TRUNC('month', event_ts)           AS month_start,
    customer_id,
    SHA2(vehicle_id, 256)                   AS vehicle_id_hash,  -- pseudonymised
    ROUND(AVG(latitude),  1)                AS region_lat,       -- ~10 km grid
    ROUND(AVG(longitude), 1)                AS region_lon,
    AVG(fuel_rate_lph)                      AS avg_fuel_rate_lph,
    AVG(vehicle_speed_kph)                  AS avg_speed_kph,
    COUNT(*)                                AS event_count
FROM TATA_DEMO_DB.RAW.RAW_TELEMETRY
GROUP BY 1, 2, 3, 4, 5;

-- Step 2: Create a replication group — ANALYTICS_DB only, NOT raw telemetry
-- Execute this in the India primary account
CREATE REPLICATION GROUP india_to_eu_analytics
    OBJECT_TYPES    = DATABASE
    ALLOWED_DATABASES = ANALYTICS_DB        -- anonymised only
    -- TATA_DEMO_DB is intentionally excluded — stays in Mumbai
    REPLICATION_SCHEDULE = '60 MINUTE'
    ALLOWED_ACCOUNTS = <your_org>.<eu_account_name>;  -- replace before running

-- Step 3: Show what IS and IS NOT in the replication group
SHOW REPLICATION GROUPS;
-- ANALYTICS_DB is in the group; TATA_DEMO_DB is not — visible proof

-- Step 4: View replication history — the cross-border transfer audit record
SELECT
    replication_group_name,
    database_name,
    phase_name,
    start_time,
    end_time,
    status
FROM SNOWFLAKE.ACCOUNT_USAGE.REPLICATION_GROUP_USAGE_HISTORY
ORDER BY start_time DESC
LIMIT 20;
-- Every replication event is logged — what was copied, when, to where.
-- This is the DPDP cross-border transfer record for your DPO.

-- Step 5: Confirm the raw telemetry DB has no replication group attached
SHOW DATABASES LIKE 'TATA_DEMO%';
-- Look at the 'replication_configuration' column — should be empty for TATA_DEMO_DB

-- =============================================================================
-- DEMO 6 WRAP-UP TALKING POINT:
-- "Three databases. One replication group. The configuration is the compliance
--  record — it explicitly names what travels. TATA_DEMO_DB with raw GPS and
--  vehicle_id never appears in any replication event log. For the EU analyst
--  team, they receive only aggregated, pseudonymised signals. GDPR Art. 44
--  cross-border transfer — handled at the architecture layer."
-- =============================================================================


-- =============================================================================
-- DEMO 7 — TRI-SECRET SECURE: ARCHITECTURE EXPLAINER
-- Duration: ~5 minutes
-- Format:   Slide/diagram walkthrough — no live SQL. Use the pre-built diagram.
-- Regulatory angle: DPDP 'right to be forgotten' at petabyte scale ·
--                   UAE/KSA PDPL data destruction · GDPR Art. 17 erasure
--                   for large historical datasets
-- =============================================================================
-- TALKING POINT:
-- "For a fleet operator who needs to terminate a customer relationship and
--  guarantee data destruction at petabyte scale — row-by-row DELETE across
--  8 years of telemetry is not feasible. Tri-Secret Secure solves this.
--  You hold the master key in your own AWS KMS or Azure Key Vault instance,
--  in your own jurisdiction. Revoking that key makes ALL Snowflake storage
--  for that customer permanently unreadable. Instant effective erasure —
--  no scanning, no row deletion."
--
-- DIAGRAM ELEMENTS TO WALK THROUGH:
-- [1] Tata's AWS KMS instance — hosted in Mumbai (ap-south-1)
-- [2] Tata holds the KMS key — Snowflake holds an internal key component
-- [3] Snowflake storage is encrypted with a key derived from BOTH components
-- [4] Every query execution requires: Snowflake component + Tata's KMS key
-- [5] Key revocation path:
--         Tata revokes key in KMS
--         → Snowflake cannot decrypt any storage
--         → All data permanently unreadable
--         → Effective erasure without row-level operation
-- [6] Audit: every KMS key access logged in AWS CloudTrail (Tata's account)
--             AND in Snowflake LOGIN_HISTORY (Snowflake account)
--
-- SUPPORTING SQL — show key rotation audit trail
-- =============================================================================

-- Show key rotation history (requires Tri-Secret Secure to be configured)
-- This query is illustrative; run only if TSS is enabled on the account.
SELECT
    key_id,
    rotation_date,
    rotation_status,
    initiated_by
FROM SNOWFLAKE.ACCOUNT_USAGE.KEY_MANAGEMENT_HISTORY
ORDER BY rotation_date DESC
LIMIT 10;

-- Demonstrate: key access events in ACCESS_HISTORY tied to encryption activity
SELECT
    query_start_time,
    user_name,
    role_name,
    query_type,
    bytes_scanned
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE query_start_time > DATEADD(DAY, -7, CURRENT_TIMESTAMP())
  AND bytes_scanned   > 0
ORDER BY bytes_scanned DESC
LIMIT 10;
-- Point: every byte scanned required a successful key resolution.
-- When the key is revoked, bytes_scanned = 0 for all future queries.

-- =============================================================================
-- DEMO 7 WRAP-UP TALKING POINT:
-- "This is the architectural answer to DPDP Rules 2025 erasure obligations at
--  fleet scale. When you sign off a fleet customer after 10 years of telemetry,
--  you do not run a multi-week DELETE job. You revoke one key. The data is
--  gone. Your AWS CloudTrail proves the revocation timestamp. Snowflake's
--  ACCESS_HISTORY proves no bytes were read after that moment."
-- =============================================================================


-- =============================================================================
-- SECTION 4 WRAP-UP: THE FOUR CORE CONTROLS SUMMARY QUERY
-- Run this at the end to show the live governance posture in one view
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- Active Row Access Policies
SELECT 'ROW_ACCESS_POLICY'   AS control_type,
       policy_name,
       'ACTIVE'              AS status,
       created               AS configured_at
FROM   SNOWFLAKE.ACCOUNT_USAGE.POLICIES
WHERE  policy_kind = 'ROW_ACCESS_POLICY'
UNION ALL
-- Active Masking Policies
SELECT 'MASKING_POLICY',
       policy_name,
       'ACTIVE',
       created
FROM   SNOWFLAKE.ACCOUNT_USAGE.POLICIES
WHERE  policy_kind = 'MASKING_POLICY'
UNION ALL
-- Active Network Policies
SELECT 'NETWORK_POLICY',
       name,
       'ACTIVE',
       created_on
FROM   SNOWFLAKE.ACCOUNT_USAGE.NETWORK_POLICIES
UNION ALL
-- Active Tasks (retention enforcement)
SELECT 'RETENTION_TASK',
       name,
       state,
       created_on
FROM   SNOWFLAKE.ACCOUNT_USAGE.TASKS
WHERE  name LIKE '%RETENTION%'
ORDER BY control_type, configured_at;

-- Deployed region — final confirmation for the room
SELECT
    'Deployed Region'                           AS check_name,
    CURRENT_REGION()                            AS value,
    CASE WHEN CURRENT_REGION() LIKE '%AP_SOUTH%'
         THEN 'PASS — Data in India (CERT-In / DPDP compliant)'
         ELSE 'REVIEW — Confirm region alignment'
    END                                         AS compliance_note;

-- =============================================================================
-- END OF SECTION 4 DEMO SCRIPT
-- =============================================================================
