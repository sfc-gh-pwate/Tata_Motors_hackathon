# Section 4 — Presenter Notes & Objection Handler
## Data Locality, Privacy & Legislation
**Tata Motors NewCo Datawarehouse Workshop | April 2026 | Confidential**

---

## 45-Minute Delivery Runsheet

| Time | Activity | File / Action |
|------|----------|---------------|
| 0–2 min | Opening frame | Verbal — see script below |
| 2–9 min | India regulatory map | Slide 4 → Demo 1 (Row Access Policy) |
| 9–16 min | GPS masking live | Demo 2 (Dynamic Data Masking) |
| 16–23 min | Retention & erasure | Demo 3 (Retention Task) |
| 23–28 min | Audit log | Demo 4 (ACCESS_HISTORY) |
| 28–32 min | Network policy | Demo 5 (IP restriction) |
| 32–39 min | Cross-border architecture | Demo 6 (Replication group) |
| 39–44 min | Tri-Secret Secure | Demo 7 (diagram + key rotation SQL) |
| 44–45 min | Governance posture summary | Wrap-up query at end of SQL file |

---

## Opening Frame (Verbatim — 2 minutes)

> "We are going to show you the Snowflake controls that map directly to each regulatory requirement. You apply the legal interpretation; we show you the switch.
>
> Snowflake's architecture separates compute from storage. Data never moves unless you explicitly configure it to. That is the foundational data-residency guarantee for all three jurisdictions — India, EU, and the Middle East.
>
> We will cover each in turn, then demonstrate four core controls — retention, access, encryption, and auditability — live in the platform. Every point we make will be backed by a running query or a visible configuration, not a slide."

---

## Jurisdiction Reference Card

### India — DPDP Act 2023 / DPDP Rules 2025 / CERT-In

| Requirement | Regulatory Source | Snowflake Control | Demo |
|-------------|------------------|-------------------|------|
| Data stays in India | DPDP 2023 | AWS Mumbai (ap-south-1) account | `SELECT CURRENT_REGION()` |
| Purpose limitation | DPDP Rules 2025 | Row Access Policy + Column Masking | Demo 1, Demo 2 |
| Erasure on consent withdrawal | DPDP Rules 2025 | `DELETE` + `DATA_RETENTION_TIME_IN_DAYS = 0` | Demo 3 |
| Log retention 180 days | CERT-In directions | `ACCOUNT_USAGE` retains 365 days, in-region | Demo 4 |
| Access from Indian jurisdiction | CERT-In directions | Network Policies (IP allowlist) | Demo 5 |
| 6-hour incident reporting | CERT-In directions | Snowflake Alerts → SIEM pipeline | Demo 4 |
| Cross-border transfer safeguards | DPDP 2023 | Explicit replication groups — PII excluded | Demo 6 |

### European Union — GDPR

| GDPR Requirement | Article | Snowflake Control | Demo |
|------------------|---------|-------------------|------|
| Data residency in EU | Art. 44 | AWS Frankfurt / GCP Europe-West account | N/A — architecture |
| Data Processing Agreement | Art. 28 | Snowflake standard DPA (request from account team) | N/A |
| Cross-border transfer safeguards | Art. 46 | SCCs + replication audit log as transfer record | Demo 6 |
| Right to erasure | Art. 17 | Hard DELETE + pseudonymisation via masking | Demo 3 |
| Data minimisation | Art. 5 | Column-level masking by role | Demo 2 |
| Breach forensics / 72-hr window | Art. 33 | `LOGIN_HISTORY` + `ACCESS_HISTORY` timeline | Demo 4 |
| Consent-based access revocation | Art. 7 | Row Access Policy reads from consent reference table | Demo 1 |

### Middle East — UAE & KSA

| Country | Snowflake Region | Framework | Key Control |
|---------|-----------------|-----------|-------------|
| UAE | Azure UAE North | Federal PDPL, DIFC, ADGM | Replication exclusions + Tri-Secret Secure |
| KSA | AWS Bahrain (me-south-1) | NDMO / KSA PDPL | **Confirm dedicated KSA region** with Snowflake account team — do not overclaim |

> **Presenter note:** Be explicit about KSA. Say: *"AWS Bahrain is the nearest available region today. If NDMO requires sovereign in-KSA deployment, that is a separate commercial discussion with Snowflake's enterprise team — we will not claim availability we cannot confirm."* This builds credibility.

---

## Cross-Border Architecture: Three Options

Present all three. Recommend Option A as strictest compliance. Acknowledge Option B is more operationally practical for analytics. Let Tata choose.

### Option A — Account-per-Region *(Recommended for strict compliance)*
- Separate Snowflake accounts: India (Mumbai), EU (Frankfurt), UAE (Azure UAE North)
- Raw personal data never leaves its jurisdiction account
- Cross-region analytics only on aggregated, non-personal datasets via Secure Data Sharing
- **Trade-off:** Higher operational overhead managing 3+ accounts

### Option B — Hub with Aggregation Layer
- Jurisdiction accounts hold raw data
- Central analytics account receives only anonymised/aggregated signals via replication groups with explicit column exclusions
- Masking policies applied before any data leaves the source account
- **Trade-off:** Requires rigorous definition of "anonymised" under each framework

### Option C — Controlled Replication with Audit
- Single primary account in India; cross-region replicas
- Replication groups explicitly exclude PII schemas
- Full audit log of every replication event
- **Trade-off:** Simpler to manage but requires strict schema governance — one misconfigured replication group addition breaks the model

---

## Key Objections and Responses

### Objection 1: "We need a dedicated cloud region in India — not shared infrastructure."

**Response:** Snowflake runs on dedicated infrastructure within AWS and Azure regions. It is not multi-tenant at the infrastructure layer — your account's storage is isolated in your own S3 bucket prefix. For sovereign cloud requirements above this, Snowflake has government and sovereign cloud options in select markets. This is a commercial discussion with Snowflake's enterprise team — be explicit about what is available today vs. what requires a separate track.

---

### Objection 2: "How do we prove CERT-In log data never left India?"

**Response:** `ACCOUNT_USAGE` views are internal to the account, provisioned in Mumbai. They are not replicated unless you explicitly configure a replication group that includes them — which we would not recommend for a CERT-In compliant setup.

Run this live:
```sql
SELECT CURRENT_REGION();  -- Returns: AWS_AP_SOUTH_1
```
The region is queryable, auditable proof. If a written attestation is needed, that is a commercial/legal request to Snowflake — but the technical evidence is the region query in your own account.

---

### Objection 3: "What about DPDP's requirement for a Consent Manager?"

**Response:** Snowflake is the enforcement layer, not the consent management front-end. The integration pattern:
1. Your consent management system writes consent status to a Snowflake reference table (`consent_status` column)
2. Row Access Policies read from that table — access is blocked the moment consent is withdrawn
3. A Scheduled Task fires on consent withdrawal to trigger deletion

The platform's role is enforcement and audit. The consent UI is your application layer.

---

### Objection 4: "Is Snowflake certified for DPDP compliance?"

**Response:** Snowflake holds ISO 27001, SOC 2 Type II, PCI DSS, and CSA STAR. DPDP certification frameworks are still being established by the Data Protection Board of India — no cloud vendor can truthfully claim DPDP certification today.

What matters is demonstrable controls: data residency, access control, deletion, and audit — all of which we have just shown live. Do not claim certification that does not exist. Tata's team will know if you overclaim, and it will cost you credibility for the rest of the session.

---

### Objection 5: "GPS at 1 Hz is a lot of personal data. How do we manage the volume under DPDP?"

**Response:** Two mechanisms working together — show Demo 2 and Demo 6 back-to-back:

1. **Demo 2 (Masking):** GPS precision is reduced at the query layer for roles that do not require full resolution — data minimisation in practice, no ETL required
2. **Demo 6 (Replication):** Cross-border analytics receive only aggregated route statistics — raw GPS coordinates stay in Mumbai
3. **Demo 3 (Retention):** High-precision GPS trail ages out automatically on the DPDP-compliant schedule your DPO agrees

---

### Objection 6: "What if Tata's fleet expands into a new jurisdiction mid-contract — South Africa, Southeast Asia?"

**Response:** The account-per-region model scales horizontally. Adding a new jurisdiction is:
1. Provision a new account in the appropriate region
2. Configure replication groups to exclude personal data
3. Apply the same governance policies (masking, row access, retention) replicated from a central governance database

The operational model does not change — only the account count increases. This is a provisioning activity, not a re-architecture.

---

### Objection 7: "Tri-Secret Secure sounds complex to operate. What happens if Tata accidentally revokes the key?"

**Response:** Key revocation is an explicit, multi-step operation in AWS KMS or Azure Key Vault — it requires deliberate administrative action with its own IAM permissions and approval workflow. Snowflake also provides a grace period before data becomes permanently unreadable, allowing key restoration in an accidental revocation scenario. For the right-to-erasure use case, intentional revocation is the design goal — the "complexity" is a feature, not a bug.

---

## Data Classification Reference — Tata Telemetry Fields

| Field | Privacy Classification | Notes |
|-------|----------------------|-------|
| `customer_id`, `vehicle_id` | Personal data (DPDP, GDPR) | Links to a natural person — the operator/driver |
| `latitude`, `longitude` | Personal data — sensitive | 1 Hz GPS trail is route-identifying |
| Harsh braking/acceleration signals | Behavioural personal data | Driver behaviour profiling |
| `tamper_alert` | Security-sensitive | Operational integrity signal |
| Dashcam video metadata | Highest sensitivity | In-region only; no cross-region replication |
| J1939 engine signals (no `vehicle_id`) | Can be anonymised | Safe for cross-region analytics once pseudonymised |
| `fuel_rate_lph`, `engine_rpm` aggregated | Non-personal aggregate | Safe in replication group for EU analytics |

---

## Pre-Session Checklist

- [ ] Snowflake account confirmed in `AWS_AP_SOUTH_1` (Mumbai) — run `CURRENT_REGION()` and screenshot
- [ ] All SQL worksheets loaded in Snowsight, labelled Demo 1 through Demo 7
- [ ] Sample data inserted (10,000 rows, both customers) — verify `SELECT COUNT(*) FROM TATA_DEMO_DB.RAW.RAW_TELEMETRY`
- [ ] All roles created and confirmed with `SHOW ROLES LIKE '%CUSTOMER%'`
- [ ] Demo 6 replication group: confirm EU account name is filled in before running (placeholder in SQL)
- [ ] Tri-Secret Secure diagram slide loaded and on standby for Demo 7
- [ ] `GOVERNANCE_WH` warehouse is resumed and available
- [ ] Network policy IPs updated to real corporate CIDRs (Demo 5 uses example blocks)
- [ ] `ACCOUNT_USAGE` queries confirmed to return rows (may have up to 45-min latency on fresh accounts)

---

*Platform mechanics only. Legal interpretation is yours.*
