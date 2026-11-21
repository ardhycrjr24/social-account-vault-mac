# Development Roadmap — Social Account Vault

## Implementation Phases

### Phase 1: Environment Inspection & Project Scaffolding [COMPLETED]
- [x] Inspect Apple Silicon / macOS environment and directory structure.
- [x] Create Xcode project (`SocialAccountVault.xcodeproj`) and scheme.
- [x] Configure Swift Package Manager manifest (`Package.swift`) targeting macOS 14+, Swift 6 strict concurrency.
- [x] Configure SwiftData schema and SQLite `ModelContainer` factory.
- [x] Implement native macOS entry point (`SocialAccountVaultApp.swift`).
- [x] Implement sidebar navigation (`SidebarView`, `MainNavigationView`) and placeholder views.
- [x] Establish testing framework and automated verification scripts.

---

### Phase 2: Data Models & Persistence Foundation [COMPLETED]
- [x] Implement complete data persistence operations for all 4 entities.
- [x] Implement Platform Category management and default seeder execution.
- [x] Implement `VaultDataService` repository with audit logging and invariant validation.
- [x] Verify database schema migration and persistence across application reboots.
- [x] Add persistence unit tests for data integrity, restart persistence, and cascade/nullify rules.

---

### Phase 3: Dashboard & Account CRUD [COMPLETED]
- [x] Implement real-time reactive Dashboard with aggregated SwiftData queries.
- [x] Implement Add Account native macOS modal sheet with validation.
- [x] Implement Edit Account form.
- [x] Implement Account Search and multi-category filtering.
- [x] Implement Archive and Restore functionality.
- [x] Implement Delete Account with native confirmation dialog.

---

### Phase 4: Account Details, Official Website Access & Audit Logs
- [ ] Implement comprehensive Account Detail view.
- [ ] Implement AppKit `NSWorkspace` URL opening with strict scheme validation.
- [ ] Implement custom key-value metadata manager (`AccountDetail`).
- [ ] Implement `ActivityLog` tracking for account creation, edits, and checks.
- [ ] Implement Notes editor with rich formatting.

---

### Phase 5: Backup, Export & Portability (BELUM TERSEDIA DI V1 — Coming Soon)
> Fitur export/backup **belum diimplementasikan** dan kontrol UI dinonaktifkan. Bukan bagian V1.
- [ ] Implement JSON export service.
- [ ] Implement CSV export service.
- [ ] Implement SQLite database snapshot service.
- [ ] Implement JSON import service with schema validation and conflict resolution.
- [ ] Implement native file save and open dialogs.

---

### Phase 6: Quality Assurance, Verification & Final Polish
- [ ] End-to-end integration tests.
- [ ] UI verification **Dark Appearance** (manual/interactive) — arah produk V1 adalah **dark-only** (`preferredColorScheme(.dark)`); **Light Appearance di luar scope V1** dan bukan item yang belum selesai. QA visual & interaksi manual masih outstanding.
- [ ] Performance profiling with Instruments (memory leaks, CPU utilization).
- [ ] Final build verification and release packaging.
