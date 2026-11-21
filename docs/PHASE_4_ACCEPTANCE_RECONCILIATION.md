# Phase 4 — Acceptance Reconciliation & Test Matrix (Status: 2026-11-21)

Dokumen ini adalah **reconciliation berbasis bukti aktual**, dibuat pada TASK 5. Dokumen spesifikasi asli (`PHASE_4_SPECIFICATION.md`, `PHASE_4_DATABASE_DESIGN.md`, `PHASE_4_ACCEPTANCE_CRITERIA.md`) **tidak diubah**. Status di bawah menggantikan matrix lama yang berisi 10 nama test yang tidak pernah ada di repository.

**Baseline bukti:** commit `002ed72` + TASK 0–5 (belum di-commit). Build Swift 6 clean, 136 test / 13 suite PASS, static audit 248/248, scanner regression 43/43.

---

## 1. Tabel 32 Acceptance Criteria

Legend: **PASS** = implementasi + test nyata · **PARTIAL** = sebagian · **FAIL** = belum · **BLOCKED** = butuh keputusan produk · **N/A** = dengan alasan.

| ID | Status | Bukti implementasi | File / fungsi | Test pembuktian |
|---|---|---|---|---|
| AC-MOD1-1 CRUD & UUID immutable | PASS | mutate in-place, UUID tidak regenerate | `VaultDataService.createAccount/updateAccount`, `Account` | `testCRUDPersistence`, `testUpdateAccountInPlaceWithoutDuplication` |
| AC-MOD1-2 max 100 char | PASS | guard nama & username | `VaultDataService` | `testFieldLengthBounds`, `testAddAccountInputValidation` |
| AC-MOD1-3 Purpose classification | PASS | enam enum V1 disetujui produk (lihat §4) & dipakai di UI/service | `AccountType.swift`, `AddAccountView`, `VaultDataService` | `testAccountInstantiation`, `testAddAccountViewPlatformInitialization` |
| AC-MOD2-1 Platform identifier format | PASS | YouTube `UC...`, AdSense `pub-...` per-key | `MetadataValidator.validateIdentifier`, `setStandardMetadata` | `testYouTubeIdentifier`, `testPublisherIdentifier` |
| AC-MOD2-2 Advisory platform detection | FAIL — **DEFERRED TO V1.1** (known gap yang disetujui pemilik produk, bukan release blocker V1) | belum ada deteksi otomatis dari username/URL | — | — |
| AC-MOD3-1 Mark checked + log | PASS | service + log "Status Checked" | `VaultDataService.markChecked` | `testMarkChecked`, `testAccountDetailViewStatusCheck` |
| AC-MOD3-2 Expiration badges | PASS | badge 30/60/90/expired, archived none | `AccountLifecycle`, Dashboard/Detail/List | `testWithin30/60/90`, `testExpired`, `testArchivedNoNotification`, `testBoundaries` |
| AC-MOD3-3 Soft archive & cascade delete | PASS | archive idempotent, cascade .cascade, 2-step confirm | `VaultDataService.archiveAccount/restoreAccount/deleteAccount` | `testArchive`, `testRestore`, `testRepeatedArchive`, `testRepeatedRestore`, `testDeleteCascade`, `testDetailPreserved`, `testLogsPreserved` |
| AC-MOD4-1 Zero-credential invariant | PASS | scanner statis + runtime hardened | `AccountDetail.validate`, `VaultDataService`, `verify_code_integrity.py` | `testAccountCredentialRejection`, `testReject*Credentials`, `testCredentialBlocked`, 43 regression checks |
| AC-MOD4-2 Masked phone | PASS | service reject >4 unmasked digits | `MetadataValidator.validateRecoveryPhoneHint`, `setRecoveryPhoneHint` | `testPhoneHint`, `testPhone`, `testRecoveryPhoneHint` (MetadataValidationTests) |
| AC-MOD4-3 Recovery email | PASS | regex + credential keyword, kosong dibolehkan | `MetadataValidator.validateRecoveryEmail`, `setRecoveryEmail` | `testRecoveryEmail`, `testEmptyRecoveryEmail` |
| AC-MOD4-4 2FA enum tracking | PASS | enum + UI + service + matriks kombinasi ditegakkan (TASK 10.1): enabled→method≠none, disabled/unknown→none, enforcedByOrg→semua; storage FAILED memblokir; data lama tidak ditulis ulang | `TwoFactorStatus.allows`, `VaultDataService.setTwoFactor`, `AccountDetailEditorView` | `TwoFactorCombinationTests`: `testValidCombinationsAccepted`, `testInvalidCombinationsRejected`, `testDirectServiceValid`, `testDirectServiceInvalidNoMutation`, `testStorageFailedStillBlocks`, `testLegacyDataUntouched`, `testErrorHasNoSensitiveData` |
| AC-MOD5-1 Hardware name max 100 | PASS | guard 100 char | `VaultDataService.setDeviceName` | `testDeviceOS` (nama perangkat), `testDeviceName` via editor tests |
| AC-MOD5-2 OS enum | PASS | DeviceOSType via service + UI | `setDeviceOS`, editor Picker | `testDeviceOS`, `testDeviceOS via enum` |
| AC-MOD5-3 Workstation context | PARTIAL | key tersedia, UI standard metadata bisa menyimpan; kurasi khusus belum | `setStandardMetadata` | `testTypedMetadataWrites` |
| AC-MOD6-1 Monetization status enum | PASS | enum + badge di detail | `MonetizationStatus`, `AccountDetailView` | `testMonetization` related |
| AC-MOD6-2 Payout & currency | PASS | validator monthly/net30/biweekly + ISO 3 | `MetadataValidator.validateIdentifier(.payout*)`, editor | `testMonetization`, `testMonetization metadata via validator` |
| AC-MOD6-3 Monetization audit log | PARTIAL | `setStandardMetadata` emits log "Updated"; tidak ada dedicated monetization audit test | `VaultDataService.setStandardMetadata` | `testLogsSanitized` (generik) |
| AC-MOD7-1 Notes ≤ 4000 | PASS | guard create/update | `VaultDataService` | `testFieldLengthBounds` |
| AC-MOD7-2 Notes credential scanner | PASS | runtime scanner hardened | `VaultDataService` | `testServiceRejectsCompoundCredentialsInNotes` |
| AC-MOD7-3 Idempotent notes update | PASS | `hasChanges` guard | `VaultDataService.updateAccount` | `testUpdateAccountAuditDeduplicationAndIdempotency` |
| AC-MOD8-1 HTTPS enforcement | PASS | https only, dangerous schemes blocked | `URLSafetyValidator.classify`, `SafeLinkButton` | `testHTTPSValid`, `testDangerousSchemes`, `testHTTPHandling` |
| AC-MOD8-2 Canonical domain match | PASS | allowlist produksi kini berisi 4 root domain kanonik terverifikasi (youtube/instagram/facebook/tiktok); dot-boundary + fake-suffix rejection aktif; loader fail-closed | `URLSafetyValidator.matchesAllowedDomain`, `DomainRegistryLoader`, `OfficialDomains.json` | `DomainRegistryV1Tests`: `testCanonicalRootsAccepted`, `testSubdomainsAccepted`, `testFakeSuffixRejected`, `testOnlyFourDomains`, `testUnlistedWarning`; plus `testExactMatch`, `testDotBoundary`, `testFakeSuffix` |
| AC-MOD8-3 Divergent domain dialog | PASS | warning → hostname + alasan + konfirmasi | `SafeLinkButton` | `testWarningRequiresConfirmation`, `testURLWarning` |
| AC-MOD8-4 Phishing heuristics | PARTIAL | 7 vektor diuji; redirect/shortener belum | `URLSafetyValidator` | `testUserinfo`, `testPunycode`, `testHomograph`, `testIPAddress`, `testPorts` |
| AC-MIG-1 Representative fixture | PASS | fixture 5+ akun, archived, optional | `MigrationTests`, fixture SHA `ba5445d0…` | `testPreMigrationCounts`, `testCanonicalFixtureIntegrity` |
| AC-MIG-2 Data preservation | PASS | counts + UUID identik | `MigrationTests` | `testPostMigrationPreservation` |
| AC-MIG-3 Default values | PASS | 8 field default aman | `Account`, `MigrationTests` | `testNewFieldDefaults`, `testPasswordLastRotatedDateIsAllowedField` |
| AC-MIG-4 Failure handling & halt writes | PASS | jalur production boot THROWS + guard; test jalur boot nyata | `DatabaseConfiguration.openProductionContainer`, `StorageCoordinator`, `VaultDataService.guardWritable`, banner `MainNavigationView` | `testPersistentContainerOpensReady`, `testFailureHasNoAutomaticInMemoryFallback`, `testWritesRejectedWhenStorageFailed`, `testOriginalFilePreservedAfterFailure`, `testRecoveryAfterProblemFixed`, `testMigrationFailurePreservesDiskFile` |
| AC-SWIFT-1 Complete concurrency | PASS | build 0 warning project | `Package.swift` StrictConcurrency | `swift build --build-tests`, static audit |
| AC-SWIFT-2 Sendable/Hashable/Identifiable | PASS | 0 `@unchecked Sendable` | semua enum/model | static audit 248/248 |
| AC-SWIFT-3 MainActor UI | PASS | @MainActor view/service/coordinator | `StorageCoordinator`, `VaultDataService` | static audit + compile |

**Ringkasan (32 criteria):** PASS 28 · PARTIAL 3 · FAIL 1 · BLOCKED 0. FAIL = AC-MOD2-2 (DEFERRED TO V1.1). Total criteria tetap 32.

---

## 2. Test Matrix Aktual (menggantikan matrix lama)

Sepuluh nama test di matrix lama TIDAK ditemukan di repository. Tabel berikut memetakan **AC → test yang benar-benar ada**:

| AC lama (nama tidak ada) | Test aktual yang membuktikan | File |
|---|---|---|
| `testAccountIdentityMutationPreservesUUID` | `testCRUDPersistence`, `testUpdateAccountInPlaceWithoutDuplication` | PersistenceTests |
| `testPlatformExternalIdentifierValidation` | `testYouTubeIdentifier`, `testPublisherIdentifier`, `testUnknownIdentifier` | MetadataValidationTests |
| `testLifecycleCheckedStatusAndDomainAlerts` | `testMarkChecked`, `testWithin30/60/90`, `testExpired` | LifecycleTests |
| `testSecurityMetadataAndPhoneMaskingEnforcement` | `testPhoneHint`, `testRecoveryEmail`, `testCredentialBlocked` | MetadataValidationTests |
| `testDeviceProfileAndOSValidation` | `testDeviceOS`, `testDeviceName` | DetailEditorTests |
| `testMonetizationMetadataAuditLogging` | `testMonetization`, `testLogsSanitized` | DetailEditorTests |
| `testNotesCredentialScannerAndIdempotency` | `testServiceRejectsCompoundCredentialsInNotes`, `testUpdateAccountAuditDeduplicationAndIdempotency` | ScannerHardeningTests, PersistenceTests |
| `testCanonicalDomainMatchingAndPhishingHeuristics` | `testExactMatch`, `testDotBoundary`, `testFakeSuffix`, `testPunycode`, `testNoUnvalidatedOpenPath` | URLSafetyTests |
| `testMigrationFromActualV1DatabaseSnapshot` | `testPreMigrationCounts`, `testPostMigrationPreservation`, `testNewFieldDefaults` | MigrationTests |
| `testDatabaseFailureHandlingPreservesDiskFile` | `testFailureHasNoAutomaticInMemoryFallback`, `testOriginalFilePreservedAfterFailure`, `testMigrationFailurePreservesDiskFile` | StorageSafetyTests, MigrationTests |

Daftar test aktual per file (123 nama unik, 136 eksekusi) dapat dilihat melalui `swift test --list` dan `grep -hE "func test" Tests/SocialAccountVaultTests/*.swift`.

---

## 3. Keputusan Produk yang Dibutuhkan

### 3.1 `AccountStatus` — [SELESAI / DISETUJUI V1]
- Keputusan produk: pertahankan empat enum aktual `active, inactive, pending, suspended` (lihat §4).
- `pending` adalah raw value; label UI-nya **"Pending Review"** (bukan raw value). Dashboard `pendingCount` menghitung `.pending`.
- `pendingReview` tidak dipakai sebagai raw value; `scheduledForDecommission` ditunda ke **V1.1** (belum ada workflow dekomisioning) dan bukan bagian dari enum V1.
- Alasan: kompatibilitas `accountStatusRaw` lama dan menghindari fallback `.active` bila raw value tidak dikenali.

### 3.2 `DomainRegistry` (SELESAI — 4 domain terverifikasi)
- Registry produksi dimuat dari `OfficialDomains.json` dan berisi **empat root kanonik terverifikasi** (TASK 12.3): `youtube.com`, `instagram.com`, `facebook.com`, `tiktok.com`. Subdomain cocok via dot-boundary; fake suffix ditolak. Loader fail-closed (resource hilang/malformed → registry kosong + diagnostic).
- `DomainRegistry.specificationExamples` hanya untuk test. **AC-MOD8-2 kini PASS.**
- Batasan keamanan: allowlist domain **tidak** menjamin redirect/shortener aman; deteksi redirect lintas-domain ditunda ke **V1.1** (MOD8-4).

### 3.3 Identifier platform (BLOCKED)
- Meta Page ID, Shopee Partner ID, Cloudflare Zone ID → `unknown`. Spesifikasi tidak memberi format; tidak dibuat aturan baru.

### 3.4 Kombinasi 2FA — [SELESAI di TASK 10.1]
- Matriks kombinasi status/metode telah disetujui produk dan diterapkan di `VaultDataService.setTwoFactor` (via `TwoFactorStatus.allows(method:)`): `enabled` → semua kecuali `.none`; `disabled`/`unknown` → hanya `.none`; `enforcedByOrg` → semua termasuk `.none` (metode tidak dicatat).
- UI editor menampilkan error validasi; `guardWritable()` tetap dijalankan sebelum validasi kombinasi. Bukti: `TwoFactorCombinationTests` (11 valid + 9 invalid + storage FAILED + data lama).

### 3.5 `AccountType` — [SELESAI / DISETUJUI V1, lihat §4]

---

## 4. Keputusan Final `AccountType` & `AccountStatus` (TASK 10.2)

Pemilik produk telah menyetujui (TASK 10.2):

| Enum | Nilai V1 yang disetujui | Raw value | Catatan |
|---|---|---|---|
| `AccountType` | `personal, business, creator, brand, affiliate, administrative` | `Personal, Business, Creator, Brand, Affiliate, Administrative` | Enam nilai aktual dipertahankan. Definisi lama `brandMarketing, contentCreation, affiliateCommerce, systemAdmin` tidak dipakai di V1. |
| `AccountStatus` | `active, inactive, pending, suspended` | `Active, Inactive, Pending, Suspended` | `pending` = raw value; label UI **"Pending Review"**. `scheduledForDecommission` → **V1.1**. |

**Alasan mempertahankan enum aktual:** `accountTypeRaw` dan `accountStatusRaw` tersimpan sebagai string. Mengganti case atau raw value membuat data lama tidak dikenali dan jatuh ke fallback (`.personal` / `.active`) pada accessor di `Account.swift`, sehingga klasifikasi hilang tanpa migrasi. Tidak ada enum gabungan yang dibuat; tidak ada raw value yang diubah.

**Dampak ke AC:** AC-MOD1-3 kini PASS (enam nilai sesuai AC & source). Tidak ada acceptance criteria yang dihapus.

---

## 5. Risiko Tersisa
- Tidak ada notifikasi sistem macOS (di luar scope spec — approval email tetap di aplikasi).
- Advisory platform detection (MOD2-2) belum diimplementasi.
- Konflik enum AccountType/AccountStatus telah diselesaikan di TASK 10.2; tidak lagi menjadi keputusan terbuka.
- Redirect/shortener lintas domain tidak terdeteksi validator (defense-in-depth, bukan jaminan).
- Dashboard KPI kini menghitung total = aktif + archived (sebelumnya salah menampilkan aktif sebagai total).
- Activity dashboard sengaja tidak menampilkan `details` untuk mencegah kebocoran teks bebas.
