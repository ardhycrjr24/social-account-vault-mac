# Architecture Documentation — Social Account Vault

## 1. Architectural Style & Separation of Concerns

Social Account Vault adheres to modern modular macOS development using **Swift 6 Strict Concurrency** and **MVVM-S** (Model-View-ViewModel-Service):

```text
┌─────────────────────────────────────────────────────────────┐
│                   App Target (Executable)                   │
│                  SocialAccountVaultApp.swift                │
└──────────────────────────────┬──────────────────────────────┘
                               │ imports
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                 SocialAccountVaultCore                      │
│                                                             │
│   ┌──────────────┐   ┌──────────────┐   ┌──────────────┐   │
│   │    Views     │──>│  ViewModels  │──>│   Services   │   │
│   │ (SwiftUI/Kit)│   │ (Observation)│   │(SwiftData/FS)│   │
│   └──────────────┘   └──────────────┘   └──────────────┘   │
│          │                                      │           │
│          └──────────────────┬───────────────────┘           │
│                             ▼                               │
│                      ┌──────────────┐                       │
│                      │    Models    │                       │
│                      │ (@Model/Enum)│                       │
│                      └──────────────┘                       │
└─────────────────────────────────────────────────────────────┘
```

### Module Breakdown

1. **`SocialAccountVaultCore` (Framework / Library Target):**
   - **`Models/`:** Persistent SwiftData models (`Account`, `PlatformCategory`, `AccountDetail`, `ActivityLog`), errors (`VaultError`), and domain value types (`PlatformType`, `AccountStatus`, `MonetizationStatus`, `AccountType`, `NavigationItem`).
   - **`ViewModels/`:** Observable state objects marked with `@Observable` and `@MainActor`.
   - **`Views/`:** SwiftUI views composed with `NavigationSplitView`, native toolbars, custom materials, and SF Symbols.
   - **`Services/`:**
     - `DatabaseConfiguration`: SQLite persistence configuration in Application Support. Production path `openProductionContainer()` / `createMigratedContainer(at:)` THROWS on failure; never substitutes an in-memory store silently.
     - `StorageCoordinator`: single source of truth for storage state (`.ready`, `.failed`, `.recovering`). All writes are gated via `requireWritable()`.
     - `URLSafetyValidator`: central https/domain/userinfo/IP/port/IDN classifier. Does not open URLs.
     - `MetadataValidator`: per-key identifier validation, recovery email/phone validation, advisory results.
     - `AccountLifecycle`: deterministic expiration badge calculation (30/60/90/expired), archived accounts never notify.
     - `CategorySeeder`: Idempotent seeder for default platform categories.
     - `VaultDataService`: Validated CRUD repository enforcing zero-credential rules, category reassignment, archival, recovery metadata, 2FA/device typed updates, and automatic activity logging.
2. **`SocialAccountVaultApp` (Application Executable Target):**
   - Host target containing `@main struct SocialAccountVaultApp: App`. Configures macOS window groups, window styling, and injects the SwiftData `ModelContainer`.
3. **`SocialAccountVaultTests` (Testing Target):**
   - Test suites built with the official **Swift Testing** framework (`import Testing`, `@Suite`, `@Test`, `#expect`), testing lifecycle, disk reopening, idempotency, security invariants, and concurrency.

---

## 2. Swift 6 Concurrency Strategy

The project compiles with `-strict-concurrency=complete`. To guarantee thread-safety and eliminate data races:

1. **Zero `@unchecked Sendable`:** No manual silencing of compiler safety warnings.
2. **MainActor UI Affinity:** All SwiftUI views, ViewModels, and UI interactions execute strictly on `@MainActor`.
3. **SwiftData Threading Model:** SwiftData context operations on the UI thread operate directly on `@MainActor`. Background imports/exports use isolated child actors with independent `ModelContext` instances.
4. **Value-Type Enum Domain:** All domain enums (`PlatformType`, `AccountStatus`, `MonetizationStatus`, `AccountType`, `NavigationItem`) are immutable structs/enums conforming to `Sendable, Codable, Hashable, Identifiable`.

---

## 3. Data Layer Architecture (Phase 2)

### Repository Pattern via `VaultDataService`
Instead of performing ad-hoc context operations in Views, mutations route through `VaultDataService`:
- Validates field boundaries (account name <= 100 chars, metadata keys <= 100 chars, values <= 1,000 chars, notes <= 5,000 chars).
- Validates that metadata keys and values do not contain prohibited credential identifiers.
- Emits structured `ActivityLog` records on creation, update, archival, restoration, and category reassignment.
- Manages atomic context saves with rollback capability.

### SwiftData SQLite Storage & Durability
- Database location (App Sandbox): aplikasi ber-sandbox, jadi **lokasi efektif yang dapat ditulis** ada di dalam container app:
  `~/Library/Containers/tech.anakterubuk.SocialAccountVault/Data/Library/Application Support/tech.anakterubuk.SocialAccountVault/SocialAccountVault.sqlite`.
  OS App Sandbox mengarahkan penulisan ke container ini. Pada eksekusi **non-sandbox** (mis. probe/test terisolasi), path host
  `~/Library/Application Support/tech.anakterubuk.SocialAccountVault/SocialAccountVault.sqlite` yang dipakai; keduanya **tidak** dianggap
  setara — konteks sandbox vs non-sandbox menentukan mana yang aktif.
- Directory auto-creation via `FileManager.default.createDirectory`.
- **No silent in-memory fallback.** If the persistent store fails to open or migrate, `DatabaseConfiguration` throws a typed `VaultError`; the on-disk file (and WAL/SHM) is left untouched.
- `StorageCoordinator` owns the single storage state (`ready` / `failed` / `recovering`). `VaultDataService.requireWritable()` blocks every write when not ready — even when called directly, not only from UI.
- A non-dismissible UI error banner is shown while storage is unavailable; writes are disabled. Retry reopens the SAME file only — no deletion, reset, or empty-store substitution.
- An explicitly created in-memory container exists only as a diagnostic presentation container so SwiftUI does not crash; it never accepts user writes and never marks the app `ready`.
- Testing support: `DatabaseConfiguration.createModelContainer(at: customURL, inMemory:)` and `makeEphemeralContainer()` provide explicit test-only paths.

---

## 4. UI Navigation Hierarchy

The application features a two-column `NavigationSplitView`:
- **Sidebar (`SidebarView`):**
  - Section **Overview**: Dashboard, All Accounts
  - Section **Platforms**: YouTube, Instagram, TikTok, Facebook, Email, Affiliate & Monetization, Website & Domain
  - Section **Vault**: Archive, Settings
- **Detail View (`contentForSelection`):**
  - Dynamic routing driven by `NavigationViewModel.selectedItem`.
  - Native `.searchable` modifier bound to `viewModel.searchText`.
  - Native toolbar containing action buttons (`+` New Account) and title indicator.

---

## 5. Phase 4 Feature Components

- **`SafeLinkButton`** (`Views/Components/`): the single UI path that calls `NSWorkspace.shared.open`. It classifies every URL through `URLSafetyValidator`; `safeToOpen` opens directly, `warning` shows hostname + reasons and requires explicit confirmation, `blocked` never opens.
- **`DomainRegistry`**: production allowlist dimuat dari `OfficialDomains.json` (Bundle.module) dan memuat **4 platform V1 terverifikasi** (TASK 12.3): `youtube.com`, `instagram.com`, `facebook.com`, `tiktok.com`. Loader fail-closed (resource hilang/malformed → registry kosong + diagnostic, TIDAK fallback ke `specificationExamples`). Subdomain cocok lewat dot-boundary; fake suffix & host terdaftar palsu ditolak. `specificationExamples` tetap khusus test.
  Sumber domain: YouTube Help / Google Support (`support.google.com/youtube`, `studio.youtube.com`), Instagram Help Center (`help.instagram.com`, `www.instagram.com/accounts/login`), Meta/Facebook Help Center (`facebook.com/help/`, `business.facebook.com`), TikTok Support (`support.tiktok.com`).
  Batasan: allowlist BUKAN jaminan semua redirect aman; proteksi redirect/shortener lintas-domain belum tersedia (AC-MOD8-4, ditunda V1.1).
- **`AccountDetailEditorView`** (`Views/Accounts/`): grouped form for recovery info, 2FA, device context, direct login URL, standard metadata with advisory results, and monetization. All writes route through `VaultDataService`.
- **Dashboard** (`DashboardPlaceholderView`): KPI bar, recent accounts, platform breakdown, recent activity (details intentionally not displayed), expiration reminders from `AccountLifecycle`, and a storage status pill driven by `StorageCoordinator`.

### Known limitations (do not treat as guarantees)
- Export/backup (JSON, CSV, DB snapshot) is NOT available in V1: Settings shows disabled "Coming Soon" controls with no action handlers and no fake output.
- `URLSafetyValidator` is defense-in-depth, not an anti-phishing guarantee. It does not detect all homographs, shorteners, or cross-domain redirects.
- `MetadataValidator` reports `unknown` for identifier formats not specified by the product spec (Meta/Shopee/Cloudflare); it does not invent formats.
- `AccountStatus` V1 enum = `active, inactive, pending, suspended` (approved TASK 10.2). Raw value is `pending`; the UI label is "Pending Review" (not a raw value). `scheduledForDecommission` is deferred to V1.1. `AccountType` V1 enum = `personal, business, creator, brand, affiliate, administrative` (approved). Both enums are kept to preserve stored raw values and avoid fallback to `.active` / `.personal`.
