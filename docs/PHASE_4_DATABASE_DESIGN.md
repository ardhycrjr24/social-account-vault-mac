# Phase 4 Database Design & Migration Specification
## Social Account Vault (Native macOS)

**Project:** Social Account Vault
**Platform Target:** macOS 14.0+ (Sonoma) & macOS 15.0+ (Sequoia) — Apple Silicon ARM64
**Stack:** SwiftData, SQLite Backend, Swift 6 Strict Concurrency
**Git Baseline:** `2f65013`
**Date:** November 2026
**Document Status:** PHASE 4 SPECIFICATION APPROVED — READY FOR IMPLEMENTATION

---

## 1. Architectural Decisions Summary

1. **Adoption of Strategy C (Hybrid Typed Domain Intelligence):**
   Core universally applicable attributes are added directly to `Account` with default values. Highly variable, platform-specific attributes are managed via strongly typed domain wrappers over `AccountDetail`.
2. **Rejection of "Zero Migration Risk" Claim:**
   Schema changes are never assumed to be zero risk. Even lightweight migrations in SwiftData can trigger store recreation or deserialization failures if defaults or types collide. A migration test using a dedicated representative V1.0 SQLite fixture is mandatory before release.
3. **Preservation of Relational Constraints & Cascade Rules:**
   - `Account.id` (UUID) remains immutable.
   - `PlatformCategory` -> `Account`: 1-to-many, `.nullify`.
   - `Account` -> `AccountDetail`: 1-to-many, `.cascade`.
   - `Account` -> `ActivityLog`: 1-to-many, `.cascade`.
4. **Service-Layer Masking & Validation:**
   Recovery phone must be stored only as a 4-digit masked hint (`•••• 8899`). Full phone number storage (>4 unmasked numeric digits) is rejected at the service layer prior to database insertion.
5. **Database Failure Handling & Halting of Writes:**
   - In-memory fallback is restricted strictly to diagnostic/read-only mode.
   - In-memory storage must NEVER silently replace the production database.
   - If migration or container setup fails, the original SQLite database file must be strictly preserved without modification, truncation, or deletion.
   - All write operations must be halted to prevent silent data loss or state divergence.
   - The UI must display an explicit notification that the database failed to open or migrate.
6. **Dedicated Test Fixture Isolation:**
   The live production database (`~/Library/Application Support/...`) must never be used as a test fixture. Tests must utilize a dedicated, reproducible test fixture.

---

## 2. Target Schema Evolution (V1.0 -> V1.1 Lightweight Evolution)

```text
┌─────────────────────────┐
│    PlatformCategory     │
├─────────────────────────┤
│ id: UUID                │
│ name: String            │
│ iconName: String        │
│ displayOrder: Int       │
│ isDefault: Bool         │
│ createdAt: Date         │
│ updatedAt: Date         │
└────────────┬────────────┘
             │ 1
             │
             │ * (deleteRule: .nullify)
┌────────────▼───────────────────────────┐
│                Account                 │
├────────────────────────────────────────┤
│ id: UUID [IMMUTABLE]                   │
│ name: String                           │
│ platform: String                       │
│ username: String                       │
│ emailReference: String                 │
│ profileURLString: String               │
│ officialDashboardURLString: String     │
│ accountTypeRaw: String                 │
│ accountStatusRaw: String               │
│ monetizationStatusRaw: String          │
│ notes: String                          │
│ isArchived: Bool                       │
│ creationDate: Date                     │
│ lastCheckedDate: Date                  │
│ domainExpirationDate: Date?            │
│ createdAt: Date                        │
│ updatedAt: Date                        │
│ [NEW] directLoginURLString: String     │ (Default: "")
│ [NEW] recoveryEmailReference: String   │ (Default: "")
│ [NEW] recoveryPhoneHint: String        │ (Default: "") [MASKED HINT ONLY]
│ [NEW] twoFactorStatusRaw: String       │ (Default: "unknown")
│ [NEW] twoFactorMethodRaw: String       │ (Default: "none")
│ [NEW] primaryDeviceName: String        │ (Default: "")
│ [NEW] deviceOSRaw: String              │ (Default: "macOS")
│ [NEW] passwordLastRotatedDate: Date?   │ (Default: nil)
└────────────┬───────────────────────────┘
             │
      ┌──────┴──────────────────────┐
      │ 1                           │ 1
      │                             │
      │ * (deleteRule: .cascade)    │ * (deleteRule: .cascade)
┌─────▼───────────────────┐   ┌─────▼───────────────────┐
│      AccountDetail      │   │       ActivityLog       │
├─────────────────────────┤   ├─────────────────────────┤
│ id: UUID [IMMUTABLE]    │   │ id: UUID [IMMUTABLE]    │
│ key: String             │   │ actionType: String      │
│ value: String           │   │ details: String         │
│ createdAt: Date         │   │ timestamp: Date         │
│ updatedAt: Date         │   │ sequenceNumber: Int     │
│                         │   │ createdAt: Date         │
│                         │   │ updatedAt: Date         │
└─────────────────────────┘   └─────────────────────────┘
```

---

## 3. Detailed Field Specifications & Constraints

| Field Name | Type | Default Value | Validation & Security Constraints |
|---|---|---|---|
| `directLoginURLString` | `String` | `""` | Valid URL, scheme must be `https://`. Max 500 characters. Insecure schemes blocked. |
| `recoveryEmailReference` | `String` | `""` | Valid RFC email syntax if non-empty. Max 150 characters. Zero-credential scan. |
| `recoveryPhoneHint` | `String` | `""` | Masked hint only (`•••• 1234` or empty). Input containing >4 unmasked digits rejected by service layer. |
| `twoFactorStatusRaw` | `String` | `"unknown"` | Enum `TwoFactorStatus` (`enabled`, `disabled`, `enforcedByOrg`, `unknown`). |
| `twoFactorMethodRaw` | `String` | `"none"` | Enum `TwoFactorMethod` (`authenticatorApp`, `hardwareKey`, `smsBackup`, `passkey`, `none`). |
| `primaryDeviceName` | `String` | `""` | Hardware profile name (max 100 characters). |
| `deviceOSRaw` | `String` | `"macOS"` | Enum `DeviceOSType` (`macOS`, `iOS`, `iPadOS`, `windows`, `linux`, `other`). |
| `passwordLastRotatedDate`| `Date?` | `nil` | Date record of password rotation. Must be `<= Date.now`. |

---

## 4. Standardized Domain Keys in `AccountDetail`

Platform-specific identifiers are managed through `StandardMetadataKey` with strict service-layer validation before writing to `AccountDetail`:

```swift
public enum StandardMetadataKey: String, CaseIterable, Sendable {
    // Platform Identifiers
    case youtubeChannelID = "platform.youtube.channel_id"
    case metaPageID = "platform.meta.page_id"
    case instagramAccountID = "platform.instagram.account_id"
    case adsensePublisherID = "platform.adsense.publisher_id"
    case shopeePartnerID = "platform.shopee.partner_id"

    // Infrastructure & DNS
    case cloudflareZoneID = "infrastructure.cloudflare.zone_id"
    case primaryNameserver = "infrastructure.dns.nameserver_1"
    case secondaryNameserver = "infrastructure.dns.nameserver_2"
    case domainRegistrar = "infrastructure.domain.registrar"

    // Monetization Details
    case payoutCurrency = "monetization.payout.currency"
    case payoutSchedule = "monetization.payout.schedule"
    case affiliateNiche = "monetization.affiliate.niche"

    // Device Context
    case workstationLocation = "device.workstation.location"
    case browserProfileName = "device.browser.profile"
}
```

---

## 5. Migration Safety, Testing & Verification Protocol

### A. Dedicated Representative V1.0 Fixture
To eliminate testing on production data while ensuring thorough coverage, a dedicated test fixture will be maintained at `Tests/Fixtures/v1_migration_fixture.sqlite`. The fixture must contain a comprehensive set of test cases:
1. **Multiple Accounts:** At least 5 accounts across different categories (YouTube, Instagram, Website/Domain, Affiliate, System).
2. **Category Relationships:** Accounts linked to default and custom `PlatformCategory` records.
3. **Child Records:** Accounts with populated `AccountDetail` key-values and sequential `ActivityLog` entries.
4. **Archived Accounts:** Both active (`isArchived == false`) and archived (`isArchived == true`) accounts.
5. **Optional Value Combinations:**
   - Account A: All optional fields populated (`domainExpirationDate`, notes with multiline text, URLs).
   - Account B: Minimal fields with optional fields set to `nil` or empty strings.

### B. Pre- and Post-Migration Integrity Verification Procedure
Before any build is signed off, the following automated procedure is executed:
1. **Pre-Migration Snapshot Audit:**
   - Open fixture with V1.0 schema.
   - Record checksums and counts: total accounts, active accounts, archived accounts, total details, total logs, category mappings.
2. **Migration Execution:**
   - Initialize SwiftData `ModelContainer` configured with the Phase 4 schema against the copied fixture.
3. **Post-Migration Audit & Assertions:**
   - Assert account count, detail count, log count, and category count match pre-migration counts exactly (0 lost records).
   - Assert all account UUIDs and creation timestamps are unaltered.
   - Assert all new fields (`directLoginURLString`, `recoveryEmailReference`, `recoveryPhoneHint`, `twoFactorStatusRaw`, `twoFactorMethodRaw`, `primaryDeviceName`, `deviceOSRaw`, `passwordLastRotatedDate`) initialize cleanly to their specified default values.
   - Assert existing optional fields (both nil and populated) maintain exact pre-migration state.
   - Execute a write transaction (e.g. update status checked) to verify read-write stability post-migration.

### C. Failure Handling & Preservation Guarantee
If a migration failure occurs:
- The original SQLite file is left untouched on disk.
- In-memory fallback is allowed only as a non-persistent diagnostic mode.
- Write operations are disabled/halted in the UI and service layer.
- An explicit, actionable error message is presented to the user indicating storage failure.
