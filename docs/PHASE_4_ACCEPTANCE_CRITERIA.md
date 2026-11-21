# Phase 4 Acceptance Criteria & Verification Matrix
## Social Account Vault (Native macOS)

**Project:** Social Account Vault
**Platform Target:** macOS 14.0+ (Sonoma) & macOS 15.0+ (Sequoia) — Apple Silicon ARM64
**Stack:** Swift 6 (Strict Concurrency), SwiftUI, SwiftData (Local-First SQLite), AppKit
**Git Baseline:** `2f65013`
**Date:** November 2026
**Document Status:** PHASE 4 SPECIFICATION APPROVED — READY FOR IMPLEMENTATION

---

## 1. Acceptance Criteria for the 8 Modules

### Module 1: Account Identity & Categorization
- [ ] **AC-MOD1-1 (CRUD & UUID Invariant):** Creating, updating, or renaming an account must mutate attributes in-place while strictly preserving the immutable `account.id` (UUID).
- [ ] **AC-MOD1-2 (Input Constraints):** Display name and handle/username must enforce max 100 characters.
- [ ] **AC-MOD1-3 (Purpose Classification):** Account purpose must be validated against `AccountType` enum (`personal`, `business`, `creator`, `brand`, `affiliate`, `administrative`).
- [ ] **Test Mapping:** `ModelFoundationTests.testAccountIdentityMutationPreservesUUID`

### Module 2: Platform Information & External Identifiers
- [ ] **AC-MOD2-1 (Platform Identifier Format):** External platform identifiers (YouTube Channel ID `UC...`, AdSense Publisher ID `pub-...`, Meta Page ID) stored via `StandardMetadataKey` must be format-validated before saving into `AccountDetail`.
- [ ] **AC-MOD2-2 (Advisory Platform Recommendation):** Platform auto-detection based on username/URL patterns must suggest the category without auto-applying it without user confirmation.
- [ ] **Test Mapping:** `SecurityInvariantTests.testPlatformExternalIdentifierValidation`

### Module 3: Account Lifecycle & Verification Health
- [ ] **AC-MOD3-1 (Checked Rhythm):** Invoking "Mark Checked" must update `lastCheckedDate` to the current timestamp and emit an `ActivityLog(actionType: "Status Checked")`.
- [ ] **AC-MOD3-2 (Domain Expiration Alerting):** Accounts with a non-nil `domainExpirationDate` must display a warning status badge if expiration is within 30, 60, or 90 days.
- [ ] **AC-MOD3-3 (Soft Archive & Cascade Delete):** Archiving preserves all metadata and logs; permanent deletion triggers a two-step confirmation and cascade-deletes all associated `AccountDetail` and `ActivityLog` rows.
- [ ] **Test Mapping:** `PersistenceTests.testLifecycleCheckedStatusAndDomainAlerts`

### Module 4: Security Metadata & Zero-Credential Boundary
- [ ] **AC-MOD4-1 (Zero-Credential Storage Invariant):** Attempting to store passwords, API keys, bearer tokens, private keys, OTP secrets, or recovery codes in any field or metadata key must immediately throw `VaultError.prohibitedCredentialStorage` and halt persistence.
- [ ] **AC-MOD4-2 (Masked Phone Hint Enforcement):** Recovery phone input must strictly be stored as a masked hint (e.g. `•••• 8899`). Any input containing more than 4 unmasked numeric digits must be rejected by the service layer.
- [ ] **AC-MOD4-3 (Recovery Email Validation):** Recovery email must conform to standard RFC email syntax and must not contain embedded credential keywords.
- [ ] **AC-MOD4-4 (2FA Enum Tracking):** 2FA status and methods must be tracked exclusively via enums (`TwoFactorStatus`, `TwoFactorMethod`) without storing secrets or authenticator seeds.
- [ ] **Test Mapping:** `SecurityInvariantTests.testSecurityMetadataAndPhoneMaskingEnforcement`

### Module 5: Device & Workstation Profiles
- [ ] **AC-MOD5-1 (Hardware Identifier):** Primary device profile must accept hardware names (max 100 characters).
- [ ] **AC-MOD5-2 (OS Enum Validation):** Operating system must conform to `DeviceOSType` (`macOS`, `iOS`, `iPadOS`, `windows`, `linux`, `other`).
- [ ] **AC-MOD5-3 (Workstation Context):** Location tag and browser profile isolation context must be stored cleanly in validated `StandardMetadataKey` slots.
- [ ] **Test Mapping:** `ModelFoundationTests.testDeviceProfileAndOSValidation`

### Module 6: Monetization & Revenue Metadata
- [ ] **AC-MOD6-1 (Monetization Status Enum):** Monetization status must be tracked via `MonetizationStatus` (`notMonetized`, `applied`, `eligible`, `monetized`, `rejected`, `notApplicable`).
- [ ] **AC-MOD6-2 (Payout & Currency Constraints):** Payout schedule must follow standard intervals (`monthly`, `net30`, `biweekly`) and currency must be an ISO 3-letter code (`USD`, `IDR`, `EUR`, `SGD`).
- [ ] **AC-MOD6-3 (Audit Trail Continuity):** Updating monetization status must produce exactly one sequential `ActivityLog(actionType: "Updated")`.
- [ ] **Test Mapping:** `PersistenceTests.testMonetizationMetadataAuditLogging`

### Module 7: Operational Notes & Runbooks
- [ ] **AC-MOD7-1 (Text Capacity):** Notes must support multiline operational text up to 4,000 characters.
- [ ] **AC-MOD7-2 (Credential Scanner Defense):** Saving notes containing obvious credential markers (e.g. `bearer eyJ...`, `password: `, `-----BEGIN PRIVATE KEY-----`) must be blocked by the scanner.
- [ ] **AC-MOD7-3 (Idempotent Update):** Saving unchanged notes must return `false` and generate zero audit log entries.
- [ ] **Test Mapping:** `SecurityInvariantTests.testNotesCredentialScannerAndIdempotency`

### Module 8: Safe Official Website & Login Access
- [ ] **AC-MOD8-1 (Scheme Enforcement):** Login URLs must require `https://`. Insecure `http://`, dangerous schemes (`javascript:`, `file:`, `data:`, `ftp:`), and malformed strings must be blocked unconditionally.
- [ ] **AC-MOD8-2 (Canonical Domain Match):** An HTTPS URL whose hostname matches the canonical domain allowlist for that platform (e.g. `studio.youtube.com` -> `youtube.com`) is allowed to launch directly via `NSWorkspace.shared.open(url)`.
- [ ] **AC-MOD8-3 (Anti-Phishing & Divergent Domain Dialog):** An HTTPS URL with a non-matching hostname (e.g. `youtube.fake-login.com`, `instagram-security.org`) must trigger an explicit confirmation dialog displaying the **full destination URL and parsed hostname** before requiring user consent.
- [ ] **AC-MOD8-4 (Phishing Heuristic Evasion Tests):** The domain validator must explicitly detect and handle:
  - Exact hostname matching (`youtube.com`).
  - Valid dot-delimited subdomain boundaries (`studio.youtube.com` vs fake suffix `fakeyoutube.com`).
  - Fake suffix domain attacks (`youtube.com.attacker.com`).
  - Unicode/Punycode homograph attacks (`xn--...`).
  - Userinfo authority injection (`https://youtube.com@attacker.com/`).
  - Non-standard ports (e.g. `:8443`).
  - Cross-domain redirects.
- [ ] **Test Mapping:** `SecurityInvariantTests.testCanonicalDomainMatchingAndPhishingHeuristics`

---

## 2. Acceptance Criteria for Database Migration & Failure Handling

- [ ] **AC-MIG-1 (Representative V1.0 Fixture Migration):** A dedicated SQLite fixture (`Tests/Fixtures/v1_migration_fixture.sqlite`) containing multiple accounts, categories, details, logs, archived accounts, and populated/nil optional values must successfully open under the Phase 4 schema without errors, store recreation, or data loss.
- [ ] **AC-MIG-2 (Data Preservation Verification):** Pre- and post-migration verification must confirm that account count, detail count, log count, category relationships, and account UUIDs remain 100% identical.
- [ ] **AC-MIG-3 (Default Value Verification):** All newly added fields on `Account` must initialize to their specified default values without nil-unwrapping crashes.
- [ ] **AC-MIG-4 (Database Failure Handling & Halting of Writes):** If migration fails or the database cannot be opened:
  - The original SQLite file on disk must be left strictly untouched.
  - In-memory storage is restricted to non-persistent diagnosis mode only (never used as a silent production fallback).
  - All write operations must be halted/disabled.
  - The UI must display an explicit notification that the database failed to open or migrate.
- [ ] **Test Mapping:** `PersistenceTests.testMigrationFromActualV1DatabaseSnapshot` and `PersistenceTests.testDatabaseFailureHandlingPreservesDiskFile`

---

## 3. Acceptance Criteria for Architecture & Swift 6 Safety

- [ ] **AC-SWIFT-1 (Complete Concurrency):** The entire codebase must compile cleanly under Swift 6 with `-strict-concurrency=complete`. Zero warnings are permitted in project source code (external toolchain warnings documented separately).
- [ ] **AC-SWIFT-2 (Type Safety & Invariants):** All domain models and value objects must conform to `Sendable, Hashable, Identifiable`. Zero `@unchecked Sendable` bypasses.
- [ ] **AC-SWIFT-3 (UI MainActor Isolation):** All SwiftUI views and ViewModels must be anchored strictly to `@MainActor`.
- [ ] **Test Mapping:** `scripts/verify_code_integrity.py` and `xcodebuild -strict-concurrency=complete`

---

## 4. Master Verification Test Mapping Matrix

| Acceptance Criteria ID | Target Test Suite | Test Case Function Name | Verification Objective |
|---|---|---|---|
| `AC-MOD1-1`, `AC-MOD1-2` | `ModelFoundationTests` | `testAccountIdentityMutationPreservesUUID` | UUID immutability & string length boundary |
| `AC-MOD2-1`, `AC-MOD2-2` | `SecurityInvariantTests` | `testPlatformExternalIdentifierValidation` | ID syntax checking & advisory recommendation |
| `AC-MOD3-1`, `AC-MOD3-2` | `PersistenceTests` | `testLifecycleCheckedStatusAndDomainAlerts` | Status checked action & expiration badge |
| `AC-MOD4-1`, `AC-MOD4-2` | `SecurityInvariantTests` | `testSecurityMetadataAndPhoneMaskingEnforcement` | Zero-credential guard & 4-digit phone mask |
| `AC-MOD5-1`, `AC-MOD5-2` | `ModelFoundationTests` | `testDeviceProfileAndOSValidation` | Hardware profile & OS enum conformance |
| `AC-MOD6-1`, `AC-MOD6-3` | `PersistenceTests` | `testMonetizationMetadataAuditLogging` | Payout schedule & idempotent audit logging |
| `AC-MOD7-1`, `AC-MOD7-2` | `SecurityInvariantTests` | `testNotesCredentialScannerAndIdempotency` | 4,000 char capacity & credential scanning |
| `AC-MOD8-1` to `AC-MOD8-4`| `SecurityInvariantTests` | `testCanonicalDomainMatchingAndPhishingHeuristics`| Scheme block, dot-boundary, Punycode, authority |
| `AC-MIG-1` to `AC-MIG-3` | `PersistenceTests` | `testMigrationFromActualV1DatabaseSnapshot` | Representative fixture lightweight migration |
| `AC-MIG-4` | `PersistenceTests` | `testDatabaseFailureHandlingPreservesDiskFile` | Preservation of original file & halted writes |
| `AC-SWIFT-1` to `AC-SWIFT-3`| Static Integrity | `scripts/verify_code_integrity.py` | Complete concurrency & 0 project warnings |
