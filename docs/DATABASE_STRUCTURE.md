# Database Structure — Social Account Vault

## 1. Persistence Engine

Social Account Vault uses **SwiftData** backed by **SQLite** on macOS. Lokasi penyimpanan tergantung konteks eksekusi:

- **Aplikasi ber-sandbox (default):** lokasi efektif yang dapat ditulis berada di dalam container app:
  `~/Library/Containers/tech.anakterubuk.SocialAccountVault/Data/Library/Application Support/tech.anakterubuk.SocialAccountVault/SocialAccountVault.sqlite`.
  OS App Sandbox mengarahkan penulisan ke sini.
- **Eksekusi non-sandbox / tes terisolasi:** path host Application Support yang dipakai, mis. `~/Library/Application Support/tech.anakterubuk.SocialAccountVault/SocialAccountVault.sqlite`.

Kedua path **tidak** setara dan tidak saling menggantikan; konteks sandbox menentukan mana yang aktif.

In-memory containers (`isStoredInMemoryOnly: true`) or custom temporary SQLite file paths are utilized for isolated automated testing and preview rendering.

---

## 2. Entity Relationship Diagram (ERD)

```text
┌──────────────────────────┐
│     PlatformCategory     │
├──────────────────────────┤
│ id: UUID (PK, Unique)    │
│ name: String             │
│ iconName: String         │
│ displayOrder: Int        │
│ isDefault: Bool          │
│ createdAt: Date          │
│ updatedAt: Date          │
└────────────┬─────────────┘
             │ 1
             │
             │ * (deleteRule: .nullify)
┌────────────▼─────────────┐
│         Account          │
├──────────────────────────┤
│ id: UUID (PK, Unique)    │
│ name: String             │
│ platform: String         │
│ username: String         │
│ emailReference: String   │
│ profileURLString: String │
│ officialDashboardURL: Str│
│ accountTypeRaw: String   │
│ accountStatusRaw: String │
│ monetizationStatusRaw:Str│
│ notes: String            │
│ isArchived: Bool         │
│ creationDate: Date       │
│ lastCheckedDate: Date    │
│ domainExpirationDate:Date│
│ createdAt: Date          │
│ updatedAt: Date          │
└────────────┬─────────────┘
             │
      ┌──────┴──────────────────────┐
      │ 1                           │ 1
      │                             │
      │ * (deleteRule: .cascade)    │ * (deleteRule: .cascade)
┌─────▼────────────────────┐  ┌─────▼────────────────────┐
│      AccountDetail       │  │       ActivityLog        │
├──────────────────────────┤  ├──────────────────────────┤
│ id: UUID (PK, Unique)    │  │ id: UUID (PK, Unique)    │
│ key: String              │  │ actionType: String       │
│ value: String            │  │ details: String          │
│ createdAt: Date          │  │ timestamp: Date          │
│ updatedAt: Date          │  │ createdAt: Date          │
│                          │  │ updatedAt: Date          │
└──────────────────────────┘  └──────────────────────────┘
```

---

## 3. Entity Definitions & Delete Rules

### 3.1 `PlatformCategory`
Defines core and customizable platform categories.
- `id`: Unique UUID identifier.
- `name`: Category name (e.g. "YouTube", "Shopee Affiliate").
- `iconName`: SF Symbol name.
- `displayOrder`: Sort position in menus and sidebar.
- `isDefault`: Boolean indicating whether this is a seeded platform or user-defined.
- `accounts`: One-to-many relationship with `Account` (`deleteRule: .nullify`).
  - **Critical Architectural Decision:** Deleting a category NULLIFIES the relationship on associated accounts instead of deleting them. This guarantees that user accounts are never accidentally lost if a category is deleted or renamed.

### 3.2 `Account`
Represents an individual account entry.
- `id`: Unique UUID identifier.
- `name`: Display label (max 100 chars, e.g. "Personal Tech Channel").
- `platform`: Name of the platform matching `PlatformType` or custom category.
- `username`: Account handle (max 100 chars, e.g. `@techcreator`).
- `emailReference`: Associated recovery/login reference email address.
- `profileURLString`: Public profile URL.
- `officialDashboardURLString`: Official creator/partner dashboard link.
- `accountTypeRaw`: Raw value of `AccountType` (Personal, Business, Creator, Brand, Affiliate, Administrative).
- `accountStatusRaw`: Raw value of `AccountStatus` (Active, Inactive, Pending, Suspended).
- `monetizationStatusRaw`: Raw value of `MonetizationStatus` (Not Monetized, Applied, Eligible, Monetized, Rejected, Not Applicable).
- `notes`: Markdown or plaintext freeform notes (max 5,000 chars).
- `isArchived`: Soft-delete flag isolating accounts from active views.
- `creationDate`: Date the account was originally created on the external platform.
- `lastCheckedDate`: Date the user last verified the account's status.
- `domainExpirationDate`: Optional expiration date for domain names and SSL certs.
- `createdAt` & `updatedAt`: Automatic tracking timestamps.
- `category`: Inverse many-to-one relationship to `PlatformCategory`.
- `details`: One-to-many relationship to `AccountDetail` (`deleteRule: .cascade`).
- `activityLogs`: One-to-many relationship to `ActivityLog` (`deleteRule: .cascade`).

### 3.3 `AccountDetail`
Stores flexible non-credential metadata key-value pairs (e.g. "Channel ID", "Publisher ID", "Cloudflare Zone ID", "Nameservers").
- `id`: Unique UUID identifier.
- `key`: Metadata name (1 to 100 chars). Validated against prohibited credential keywords.
- `value`: Metadata content (1 to 1,000 chars). Validated against prohibited credential keywords.
- `createdAt` & `updatedAt`: Automatic tracking timestamps.
- `account`: Inverse relationship to parent `Account`.

### 3.4 `ActivityLog`
Maintains an immutable audit trail of actions performed on an account.
- `id`: Unique UUID identifier.
- `actionType`: Category of action (e.g., "Created", "Updated", "Archived", "Restored", "Checked", "Category Changed").
- `details`: Human-readable description of the change (max 2,000 chars).
- `timestamp`: Date and time the action occurred.
- `createdAt` & `updatedAt`: Automatic tracking timestamps.
- `account`: Inverse relationship to parent `Account`.

---

## 4. Idempotent Category Seeder

The 8 core categories are initialized at first launch via `CategorySeeder.seedDefaultCategoriesIfNeeded`:
1. YouTube (`play.rectangle.fill`)
2. Instagram (`camera.fill`)
3. TikTok (`music.note`)
4. Facebook (`person.2.fill`)
5. Email (`envelope.fill`)
6. Shopee Affiliate (`bag.fill`)
7. Google AdSense (`dollarsign.circle.fill`)
8. Website & Domain (`globe`)

**Idempotency Guarantee:**
- Queries existing categories by name.
- If already present: updates icon and order if out of sync, preserving existing associated accounts.
- If absent: inserts the category.
- Running the seeder repeatedly (e.g. on every app launch) produces no duplicates and leaves all existing user data intact.
