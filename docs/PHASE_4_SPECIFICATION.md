# Phase 4 Specification — Modular Account Intelligence
## Social Account Vault (Native macOS)

**Project:** Social Account Vault
**Platform Target:** macOS 14.0+ (Sonoma) & macOS 15.0+ (Sequoia) — Apple Silicon ARM64
**Architecture:** Swift 6 (Complete Strict Concurrency), SwiftUI, SwiftData, AppKit
**Git Baseline:** `2f65013` (Phase 3 Completed & Signed-Off)
**Date:** November 2026
**Document Status:** PHASE 4 SPECIFICATION APPROVED — READY FOR IMPLEMENTATION

---

## 1. Executive Summary

Phase 4 transforms Social Account Vault from a basic CRUD repository into an intelligent, structured metadata platform: **Modular Account Intelligence**. It introduces structured operational visibility across 8 discrete dimensions while strictly upholding the Zero-Credential Storage boundary, local-first data privacy, and Swift 6 complete concurrency safety.

---

## 2. Architecture Decisions & Technical Rationale

The following 14 architectural decisions govern the Phase 4 specification:

1. **Database Strategy — Hybrid Typed Domain Intelligence (Strategy C):**
   Extend the core `Account` entity with lightweight attributes carrying native default values, combined with a typed domain wrapper (`StandardMetadataKey`, `MetadataCategory`) over `AccountDetail`. This avoids the high complexity and relationship risks of heavy SwiftData V2 child-model migrations while preventing unvalidated freeform key-value dumps.
2. **Lightweight Migration Verification Mandate:**
   Lightweight migration must not be claimed as "zero risk." It must be formally tested against a dedicated representative V1.0 SQLite fixture containing populated accounts, categories, details, logs, archived records, and both populated/nil optional values.
3. **Database Failure Handling & Halting of Writes:**
   In-memory fallback is strictly restricted to diagnostic/read-only mode and must NEVER silently replace the production database. If migration or store initialization fails:
   - The original `SocialAccountVault.sqlite` file and its WAL/SHM artifacts must remain completely untouched and preserved.
   - All write operations must be immediately halted to prevent silent data bifurcation or unpersisted state loss.
   - The UI must display an explicit error banner informing the user that the database failed to open or migrate, providing diagnostics without silent data degradation.
4. **Preservation of UUID, Relationships, and Delete Rules:**
   Account mutations must strictly mutate records in-place without regenerating `UUID`. Cascade rules (`.cascade` for details and logs, `.nullify` for categories) are strictly preserved.
5. **Permitted HTTPS URL Dispatch:**
   URLs using the `https://` scheme whose canonical hostname matches the official allowlist for the account's platform can be opened directly in the default browser.
6. **Strict Phishing Defense & Full Destination Display:**
   HTTPS URLs whose domain does not match the canonical allowlist must not open automatically. They must trigger an explicit confirmation dialog displaying the **full destination URL and parsed hostname** before requiring explicit user approval.
7. **Comprehensive Canonical Domain Matching Heuristics:**
   Domain evaluation must be resilient against common evasion and phishing vectors:
   - *Exact matching:* `youtube.com` matches `youtube.com`.
   - *Valid subdomain boundary:* `studio.youtube.com` and `m.youtube.com` match `youtube.com` via strict dot-delimited suffix matching (`.youtube.com`).
   - *Fake suffix rejection:* `youtube.com.attacker.com` and `fakeyoutube.com` are rejected.
   - *Unicode & Punycode defense:* Punycode domains (`xn--...`) and non-ASCII confusable homoglyphs are detected and flagged as untrusted.
   - *Authority injection rejection:* URLs containing userinfo credentials (`https://youtube.com@attacker.com/`) are rejected as malformed/dangerous.
   - *Custom port handling:* Non-standard ports (e.g. `:8443`) are highlighted in the confirmation prompt.
   - *Cross-domain redirect alert:* In-app tracking/shorteners that redirect across external domains are treated as unverified destinations.
8. **Strict Blocking of Insecure, Unknown, or Malformed URLs:**
   Insecure schemes (`http://`), dangerous schemes (`javascript:`, `file:`, `data:`, `ftp:`), and malformed URL strings are unconditionally blocked with user error feedback.
9. **Recovery Phone Masked Hint Only (Service-Layer Enforcement):**
   Recovery phone input is strictly limited to a masked 4-digit hint (e.g. `•••• 8899`). Storage of full phone numbers is rejected at the service layer.
10. **Recovery Email as Sensitive Personal Data:**
    Recovery emails are treated as sensitive personal data; inputs are validated for RFC-compliant email syntax and guarded against credential leaks.
11. **Platform Detection as Advisory Recommendation Only:**
    Platform auto-detection based on username/URL patterns serves only as a non-binding suggestion; final classification remains strictly with the user.
12. **Credential Scanner as Defense-in-Depth:**
    The automated credential scanner acts as a preventive defense-in-depth filter against obvious secrets, not an absolute guarantee against all obfuscated credentials.
13. **Compiler Warning Standards:**
    Zero-warning policy applies strictly to the project's own source code under Swift 6 `-strict-concurrency=complete`. External SDK/toolchain warnings are audited and documented separately.
14. **Dedicated Test Fixture Isolation:**
    Testing migration must never use the user's live production database. A deterministic, standalone fixture (`Tests/Fixtures/v1_migration_fixture.sqlite`) is used exclusively for automated tests.

---

## 3. The 8 Intelligence Modules

```text
┌────────────────────────────────────────────────────────────────────────┐
│                        MODULAR ACCOUNT INTELLIGENCE                    │
├───────────────────┬───────────────────┬────────────────────────────────┤
│ 1. Identity       │ 2. Platform       │ 3. Lifecycle                   │
│ • Handle / Tag    │ • Custom URLs     │ • Status & Retention           │
│ • Account Purpose │ • Channel/Page ID │ • Last Checked Schedule        │
├───────────────────┼───────────────────┼────────────────────────────────┤
│ 4. Security       │ 5. Device Profile │ 6. Monetization                │
│ • 2FA Method (App)│ • Primary Device  │ • AdSense / Affiliate ID       │
│ • Recovery Email  │ • Workstation Tag │ • Payout Schedule / Tier       │
├───────────────────┴───────────────────┴────────────────────────────────┤
│ 7. Structured Notes & Runbooks        │ 8. Official Website & Login    │
│ • Operational Runbooks                │ • Strict URL Domain Heuristics │
│ • Non-sensitive Handover Notes        │ • Anti-Phishing Guard          │
└───────────────────────────────────────┴────────────────────────────────┘
```

### Module 1: Account Identity
- **Display Name & Brand Alias:** Unique operational identifier (e.g. "Creator Hub ID - Main", max 100 chars).
- **Handle / Username:** Standard platform format (`@handle`, alphanumeric ID, max 100 chars).
- **Account Purpose:** Enum V1 = `personal`, `business`, `creator`, `brand`, `affiliate`, `administrative` (rawValue: `Personal`, `Business`, `Creator`, `Brand`, `Affiliate`, `Administrative`). Enam nilai ini dipertahankan untuk kompatibilitas `accountTypeRaw` yang sudah tersimpan dan untuk menghindari jatuhnya data lama ke fallback `.personal`. Definisi lama (`brandMarketing`, `contentCreation`, `affiliateCommerce`, `systemAdmin`) tidak digunakan di V1.
- **Identity Invariant:** UUID preservation guaranteed during all updates.

### Module 2: Platform Information
- **Platform Assignment:** Strongly typed `PlatformType` or extensible custom category.
- **External Identifiers:** Dedicated metadata keys via `StandardMetadataKey` (YouTube Channel ID, Meta Page ID, AdSense Publisher ID, Shopee Partner ID, Cloudflare Zone ID).
- **Advisory Platform Detection:** Suggests platform category from input URL/handle; requires explicit user confirmation.

### Module 3: Account Lifecycle & Verification Health
- **Operational Status:** Enum V1 = `active`, `inactive`, `pending`, `suspended` (rawValue: `Active`, `Inactive`, `Pending`, `Suspended`). Nilai `pending` memiliki raw value `pending`/`Pending`; label UI-nya adalah **"Pending Review"** — label tersebut BUKAN raw value. `scheduledForDecommission` ditunda ke V1.1 karena belum ada workflow dekomisioning; bukan bagian dari enum V1. `pendingReview` tidak dipakai sebagai raw value agar data `accountStatusRaw` lama tidak jatuh ke fallback `.active`.
- **Creation Date Tracking:** Historical platform registration date.
- **Verification Rhythm (Last Checked Date):**
  - Interactive "Mark Checked" action updating `lastCheckedDate` with audit log entry.
  - Visual health badges: Green (< 30 days), Yellow (30–90 days), Orange (> 90 days / Stale).
- **Domain Expiration Alerts:** Banners for domains expiring within 30, 60, or 90 days.

### Module 4: Security Metadata (Zero-Credential Boundary)
- **STRICT PROHIBITION:** Passwords, API keys, tokens, session cookies, OTP secrets, recovery codes, and private keys are completely forbidden.
- **Recovery Email:** Validated email syntax, max 150 chars, treated as sensitive personal data.
- **Recovery Phone:** Service-layer enforced masked hint (e.g. `•••• 8899`), raw unmasked numbers (>4 unmasked digits) rejected.
- **2FA Status & Method:** Enum `TwoFactorStatus` (`enabled`, `disabled`, `enforcedByOrg`, `unknown`) and `TwoFactorMethod` (`authenticatorApp`, `hardwareKey`, `smsBackup`, `passkey`, `none`). No authenticator seeds or URIs stored.
- **Password Rotation Tracker:** `passwordLastRotatedDate` (historical timestamp only, `<= Date.now`).

### Module 5: Device & Workstation Profiles
- **Primary Assigned Device:** Hardware identifier (e.g. "MacBook Pro M1 Studio", max 100 chars).
- **Device Operating System:** Enum `DeviceOSType` (`macOS`, `iOS`, `iPadOS`, `windows`, `linux`, `other`).
- **Workstation & Browser Context:** Validated tags for physical location and browser profile isolation.

### Module 6: Monetization & Revenue Metadata
- **Monetization Status:** Enum `MonetizationStatus` (`notMonetized`, `applied`, `eligible`, `monetized`, `rejected`, `notApplicable`).
- **Partner Identifier:** Clean representation of publisher / merchant numbers.
- **Payout Cadence & Currency:** Cadence (`monthly`, `net30`, `biweekly`) and standard 3-letter ISO code (`USD`, `IDR`, `EUR`, `SGD`).
- **Audit Logging:** Monetization status change triggers automatic `"Updated"` ActivityLog.

### Module 7: Account Notes & Runbooks
- **Operational Notes:** Multiline text up to 4,000 characters for guidelines and non-sensitive runbooks.
- **Credential Scanner Defense-in-Depth:** Scans for obvious private keys, bearer tokens, or password prefixes before saving.
- **Idempotent Updates:** Unchanged notes trigger no-op and do not produce redundant audit logs.

### Module 8: Safe Official Website & Login Access

> **DomainRegistry V1 (ditetapkan produk, TASK 12.3):** allowlist produksi berisi root domain kanonik 4 platform terverifikasi — `youtube.com` (YouTube), `instagram.com` (Instagram), `facebook.com` (Facebook), `tiktok.com` (TikTok) — dimuat dari `Sources/SocialAccountVaultCore/Resources/OfficialDomains.json` via `DomainRegistryLoader`. Tanpa wildcard; subdomain mengikuti aturan dot-boundary. Domain lain (termasuk `accounts.google.com`, shortener/tracking/CDN) TIDAK dimasukkan tanpa keputusan terpisah.
- **Official Dashboard URL & Direct Login URL:** Segregated fields with dedicated launch buttons.
- **Scheme Enforcement:** Strict `https://` required for login URLs. Non-HTTPS schemes blocked.
- **Domain Matching & Anti-Phishing Guard:**
  - Allowed Canonical Match: Direct launch via `NSWorkspace.shared.open(url)`.
  - Divergent Hostname: Modal alert displaying warning and full destination URL + parsed host, requiring explicit confirmation.
  - Insecure / Malformed: Blocked with inline error message.

---

## 4. UI/UX Architecture & Error Presentation

- **Modular Detail View:** Segmented card layout (Hero Overview, Security & Devices, Monetization & Domains, Notes & Runbooks, Audit Timeline).
- **SafeLinkButton:** Visual status indicating verified domain vs unverified/external destination.
- **System Launch:** Relies entirely on `NSWorkspace.shared.open(url)` to launch default system browser, preserving OS-level sandbox isolation.
- **Database Error Banner:** If database initialization fails, a non-dismissible warning banner is shown at the top of the window stating: *"Database failed to open or migrate. Application is in read-only diagnostic mode. Writes are temporarily halted to protect your data."*
