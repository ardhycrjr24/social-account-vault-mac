import Testing
import Foundation
import SwiftData
@testable import SocialAccountVaultCore

/// Task 3 — Account Lifecycle Management regression tests.
/// Tanggal acuan tetap & data dummy; tanpa koneksi internet.
@Suite("Account Lifecycle")
struct LifecycleTests {
    private let lifecycle = AccountLifecycle()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private let now = Date(timeIntervalSince1970: 1_760_000_000) // tetap

    private func daysFromNow(_ days: Int, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: days, to: now)!
    }

    private var utcCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    // 1. Tanpa tanggal kedaluwarsa.
    @Test("1. No expiration date yields none")
    func testNoExpiration() {
        #expect(lifecycle.expirationBadge(for: nil, isArchived: false, now: now, calendar: utcCalendar) == .none)
    }

    // 2. Lebih dari 90 hari.
    @Test("2. Expiration beyond 90 days yields none")
    func testBeyond90() {
        let d = daysFromNow(120, calendar: utcCalendar)
        #expect(lifecycle.expirationBadge(for: d, isArchived: false, now: now, calendar: utcCalendar) == .none)
    }

    // 3. Dalam 90 hari.
    @Test("3. Expiration within 90 days")
    func testWithin90() {
        let d = daysFromNow(90, calendar: utcCalendar)
        #expect(lifecycle.expirationBadge(for: d, isArchived: false, now: now, calendar: utcCalendar) == .within90)
    }

    // 4. Dalam 60 hari.
    @Test("4. Expiration within 60 days")
    func testWithin60() {
        let d = daysFromNow(60, calendar: utcCalendar)
        #expect(lifecycle.expirationBadge(for: d, isArchived: false, now: now, calendar: utcCalendar) == .within60)
    }

    // 5. Dalam 30 hari.
    @Test("5. Expiration within 30 days")
    func testWithin30() {
        let d = daysFromNow(30, calendar: utcCalendar)
        #expect(lifecycle.expirationBadge(for: d, isArchived: false, now: now, calendar: utcCalendar) == .within30)
    }

    // 6. Sudah kedaluwarsa.
    @Test("6. Past expiration yields expired")
    func testExpired() {
        let d = daysFromNow(-1, calendar: utcCalendar)
        #expect(lifecycle.expirationBadge(for: d, isArchived: false, now: now, calendar: utcCalendar) == .expired)
    }

    // 7. Batas tanggal (31 → none, 0 → within30, -1 → expired).
    @Test("7. Date boundaries are exact")
    func testBoundaries() {
        #expect(lifecycle.expirationBadge(for: daysFromNow(31, calendar: utcCalendar), isArchived: false, now: now, calendar: utcCalendar) == .within60)
        #expect(lifecycle.expirationBadge(for: daysFromNow(61, calendar: utcCalendar), isArchived: false, now: now, calendar: utcCalendar) == .within90)
        #expect(lifecycle.expirationBadge(for: daysFromNow(0, calendar: utcCalendar), isArchived: false, now: now, calendar: utcCalendar) == .within30)
    }

    // 8. Akun archived tidak menghasilkan notifikasi.
    @Test("8. Archived account yields no expiration notification")
    func testArchivedNoNotification() {
        let d = daysFromNow(-5, calendar: utcCalendar)
        #expect(lifecycle.expirationBadge(for: d, isArchived: true, now: now, calendar: utcCalendar) == .none)
    }

    // Helper service READY.
    @MainActor
    private func makeReadyService() throws -> (VaultDataService, Account, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault_life_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = dir.appendingPathComponent("life.sqlite")
        let coordinator = StorageCoordinator(storeURL: db)
        _ = coordinator.bootstrap()
        let context = ModelContext(coordinator.presentedContainer!)
        let service = VaultDataService(modelContext: context, storageGate: coordinator)
        let account = try service.createAccount(name: "Dummy", platform: "YouTube")
        return (service, account, dir)
    }

    // 9. Mark as checked.
    @Test("9. Mark as checked updates date and logs")
    @MainActor
    func testMarkChecked() throws {
        let (service, account, dir) = try makeReadyService()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try service.markChecked(account)
        #expect(account.activityLogs.contains { $0.actionType == "Status Checked" })
    }

    // 10. Archive.
    @Test("10. Archive preserves account")
    @MainActor
    func testArchive() throws {
        let (service, account, dir) = try makeReadyService()
        defer { try? FileManager.default.removeItem(at: dir) }
        let changed = try service.archiveAccount(account)
        #expect(changed)
        #expect(account.isArchived)
        #expect(try service.fetchActiveAccounts().isEmpty)
    }

    // 11. Restore.
    @Test("11. Restore returns account to active")
    @MainActor
    func testRestore() throws {
        let (service, account, dir) = try makeReadyService()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try service.archiveAccount(account)
        let changed = try service.restoreAccount(account)
        #expect(changed)
        #expect(!account.isArchived)
        #expect(try service.fetchActiveAccounts().count == 1)
    }

    // 12. Archive berulang (idempotent, tanpa log duplikat).
    @Test("12. Repeated archive is idempotent")
    @MainActor
    func testRepeatedArchive() throws {
        let (service, account, dir) = try makeReadyService()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(try service.archiveAccount(account))
        #expect(!(try service.archiveAccount(account)))
        let logs = try service.fetchActivityLogs(for: account).filter { $0.actionType == "Archived" }
        #expect(logs.count == 1)
    }

    // 13. Restore berulang.
    @Test("13. Repeated restore is idempotent")
    @MainActor
    func testRepeatedRestore() throws {
        let (service, account, dir) = try makeReadyService()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try service.archiveAccount(account)
        #expect(try service.restoreAccount(account))
        #expect(!(try service.restoreAccount(account)))
        let logs = try service.fetchActivityLogs(for: account).filter { $0.actionType == "Restored" }
        #expect(logs.count == 1)
    }

    // 14. Delete confirmation flow (service-level, cascade).
    @Test("14. Delete cascades details and logs")
    @MainActor
    func testDeleteCascade() throws {
        let (service, account, dir) = try makeReadyService()
        defer { try? FileManager.default.removeItem(at: dir) }
        try service.addDetail(to: account, key: "platform.youtube.channel_id", value: "UCabcdefghij1234567890XY")
        _ = try service.markChecked(account)
        try service.deleteAccount(account)
        #expect(try service.fetchActiveAccounts().isEmpty)
    }

    // 15. Relasi AccountDetail tetap utuh setelah archive/restore.
    @Test("15. Detail relationship preserved across archive/restore")
    @MainActor
    func testDetailPreserved() throws {
        let (service, account, dir) = try makeReadyService()
        defer { try? FileManager.default.removeItem(at: dir) }
        try service.addDetail(to: account, key: "platform.youtube.channel_id", value: "UCabcdefghij1234567890XY")
        _ = try service.archiveAccount(account)
        _ = try service.restoreAccount(account)
        #expect(account.details.count == 1)
        #expect(account.details.first?.key == "platform.youtube.channel_id")
    }

    // 16. ActivityLog tetap utuh.
    @Test("16. Activity logs preserved across archive/restore")
    @MainActor
    func testLogsPreserved() throws {
        let (service, account, dir) = try makeReadyService()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try service.markChecked(account)
        let before = account.activityLogs.count
        _ = try service.archiveAccount(account)
        _ = try service.restoreAccount(account)
        #expect(account.activityLogs.count >= before + 2)
    }

    // 17. Storage FAILED memblokir semua operasi tulis lifecycle.
    @Test("17. Lifecycle writes blocked when storage FAILED")
    @MainActor
    func testWritesBlockedWhenFailed() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault_life_fail_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = dir.appendingPathComponent("corrupt.sqlite")
        try Data("CORRUPT".utf8).write(to: db)
        let coordinator = StorageCoordinator(storeURL: db)
        _ = coordinator.bootstrap()
        let context = ModelContext(coordinator.presentedContainer!)
        let service = VaultDataService(modelContext: context, storageGate: coordinator)
        let account = Account(name: "Dummy", platform: "YouTube")
        context.insert(account)
        #expect(throws: VaultError.self) { try service.markChecked(account) }
        #expect(throws: VaultError.self) { try service.archiveAccount(account) }
        #expect(throws: VaultError.self) { try service.restoreAccount(account) }
        #expect(throws: VaultError.self) { try service.deleteAccount(account) }
    }
}
