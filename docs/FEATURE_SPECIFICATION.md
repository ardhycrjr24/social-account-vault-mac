# Feature Specification — Social Account Vault

## 1. Feature Breakdown by Module

### 1.1 Dashboard Overview
- **Metric Cards:**
  - Total active accounts.
  - Accounts broken down by operational status (Active, Inactive, Pending Review, Suspended).
  - Monetization counts (Monetized, Eligible, Applied).
  - Archived count summary.
- **Platform Breakdown Grid:**
  - Card per platform displaying registered count and shortcut to filtered listing.
- **Domain & Expiration Schedule:**
  - Highlights domains expiring within 30, 60, and 90 days.

### 1.2 Account Management (CRUD)
- **Create Account:**
  - Guided form with platform selection, account name, username, email reference, URLs, type, and monetization status.
- **Edit Account:**
  - Real-time updates with SwiftData persistence.
  - Automatically updates `updatedAt` and records an entry in `ActivityLog`.
- **View Account Details:**
  - Displays comprehensive metadata, official dashboard action button, key-value metadata list, and activity history.
- **Archive & Restore:**
  - Toggle `isArchived` flag.
  - Dedicated "Archive" view to review, restore to active, or permanently delete.
- **Delete Account with Confirmation:**
  - Native AppKit/SwiftUI confirmation dialog preventing accidental loss.
  - Cascade deletion cleans up associated `AccountDetail` and `ActivityLog` records.

### 1.3 Search, Filtering, and Sorting
- **Native Searchable:**
  - Live query filtering across account name, username, email reference, and platform.
- **Category Filter:**
  - Sidebar-driven platform routing.
- **Status Filter:**
  - Quick filter by Active, Pending, or Inactive.

### 1.4 Official Website Access
- **Safe Dispatch:**
  - Uses `NSWorkspace.shared.open(url)` to open official dashboards in macOS default browser.
- **Validation:**
  - Strict URL scheme validation (`https://` or `http://`) before invoking AppKit.
- **Strict Boundary:**
  - No automated form login, no web scraping, no credential passing.

### 1.5 Backup and Portability (NOT AVAILABLE in V1)
> Status: **Coming Soon**. Fitur export/backup BELUM tersedia di V1 dan TIDAK diimplementasikan pada saat ini.
> Tombol "Export JSON", "Export CSV", dan "Backup DB" di Settings sengaja **dinonaktifkan** dengan label
> "Coming Soon"; tidak ada action handler, tidak ada output file, dan tidak ada simulasi keberhasilan.
>
> Rencana masa depan (bukan bagian V1):
- **JSON Export:** encodes all accounts, categories, details, and activity logs into a portable JSON structure.
- **CSV Export:** formats accounts into a flat CSV format for spreadsheet auditing.
- **SQLite Database Snapshot:** creates a direct binary backup of the SQLite file.
- **JSON Import with Validation:** validates schema structure before merging or restoring into SwiftData.
