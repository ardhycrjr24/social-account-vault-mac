# Project Overview — Social Account Vault

## 1. Executive Summary

**Social Account Vault** is a native macOS application engineered with Swift 6, SwiftUI, SwiftData, and AppKit for Apple Silicon Macs. It empowers digital creators, affiliate marketers, business owners, and solo operators to catalogue and maintain metadata regarding their online assets without security compromises.

### Core Value Proposition
- **Single Source of Truth:** Centralizes account names, platforms, usernames, associated emails, monetization tiers, and notes.
- **Privacy & Security Guarantee:** Explicitly excludes credential storage (no passwords, OAuth keys, or cookies).
- **Native Experience:** Feels at home on macOS with deep OS integration, NavigationSplitView, SF Symbols, AppKit NSWorkspace browser dispatch, and dark styling.
- **Local Sovereignty:** Data stays on the local disk backed by SwiftData/SQLite. Export/import is planned but not available in V1.

---

## 2. Target Platforms & Environment

- **Host Hardware:** MacBook M1 Pro (Apple Silicon ARM64)
- **Host Operating System:** macOS 14.0+ / macOS 15.0+
- **Toolchain:** Swift 6.0 Strict Concurrency (`-strict-concurrency=complete`)
- **IDE:** Xcode 16.0+
- **Project Root:** repositori git ini (path lokal bervariasi; gunakan akar repo `SocialAccountVault/` relatif).

---

## 3. Scope Boundaries (V1)

### In-Scope (Must Have)
1. **Dashboard:** Aggregated metrics (total accounts, platform breakdown, active, pending, monetized counts, domain reminders).
2. **Account CRUD:** Register, view, edit, archive, restore, and delete accounts with confirmation.
3. **8 Core Platform Categories:** YouTube, Instagram, TikTok, Facebook, Email, Shopee Affiliate, Google AdSense, Website & Domain.
4. **AppKit Browser Integration:** Validate and open official dashboards via macOS default browser without auto-login.
5. **Local Backup & Export:** NOT available in V1 — JSON/CSV export, import, and database snapshotting are deferred; UI controls are disabled with a "Coming Soon" status (no fake success).
6. **SwiftData Persistence:** Robust SQLite storage with schema versioning and cascade deletion rules.

### Out-of-Scope (Non-Goals for V1)
- Password management or credential autofill.
- Social media automation, scraping, or direct posting.
- Third-party social platform API integrations (e.g. Meta Graph API, YouTube Data API).
- Cloud synchronization (iCloud CloudKit / Firebase) in V1.
