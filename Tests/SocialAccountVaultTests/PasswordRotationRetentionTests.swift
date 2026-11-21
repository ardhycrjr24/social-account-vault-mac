import Testing
import Foundation
import SwiftData
@testable import SocialAccountVaultCore

/// TASK 11.2 — passwordLastRotatedDate historical data retention tests.
///
/// Keputusan produk: toggle OFF TIDAK menghapus tanggal historis; penghapusan hanya
/// lewat aksi eksplisit + konfirmasi. Diuji pada level service (satu sumber kebenaran).
@Suite("Password Rotation Historical Retention")
struct PasswordRotationRetentionTests {
    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    @MainActor
    private func makeService() throws -> (VaultDataService, Account, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault_retention_\\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = dir.appendingPathComponent("retention.sqlite")
        let coordinator = StorageCoordinator(storeURL: db)
        _ = coordinator.bootstrap()
        let context = ModelContext(coordinator.presentedContainer!)
        let service = VaultDataService(modelContext: context, storageGate: coordinator)
        let account = try service.createAccount(name: "Dummy", platform: "YouTube")
        return (service, account, dir)
    }

    // 1. Toggle OFF + Save mempertahankan tanggal lama.
    @Test("Toggle OFF preserves stored historical date")
    @MainActor
    func testToggleOffPreservesDate() throws {
        let (service, account, dir) = try makeService()
        defer { try? FileManager.default.removeItem(at: dir) }
        let past = now.addingTimeInterval(-86_400 * 30)
        #expect(try service.setPasswordRotationDate(account, date: past, now: now))
        // Simulasi UI: toggle OFF mengirim nil -> service tidak melakukan apa pun.
        #expect(try !service.setPasswordRotationDate(account, date: nil, now: now))
        #expect(account.passwordLastRotatedDate == past)
    }

    // 2 & 3. Toggle ON + Save memperbarui / menyimpan tanggal.
    @Test("Toggle ON updates to a new date")
    @MainActor
    func testToggleOnUpdates() throws {
        let (service, account, dir) = try makeService()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = now.addingTimeInterval(-86_400 * 30)
        let second = now.addingTimeInterval(-86_400 * 5)
        #expect(try service.setPasswordRotationDate(account, date: first, now: now))
        #expect(try service.setPasswordRotationDate(account, date: second, now: now))
        #expect(account.passwordLastRotatedDate == second)
    }

    // 4. Penghapusan eksplisit setelah konfirmasi menghapus tanggal.
    @Test("Explicit delete removes the date")
    @MainActor
    func testExplicitDelete() throws {
        let (service, account, dir) = try makeService()
        defer { try? FileManager.default.removeItem(at: dir) }
        let past = now.addingTimeInterval(-3600)
        #expect(try service.setPasswordRotationDate(account, date: past, now: now))
        #expect(try service.removePasswordRotationDate(account))
        #expect(account.passwordLastRotatedDate == nil)
    }

    // 5. Tidak ada penghapusan sebelum konfirmasi (penghapusan hanya lewat remove eksplisit).
    @Test("No removal before explicit confirmation path")
    @MainActor
    func testNoRemovalWithoutExplicitAction() throws {
        let (service, account, dir) = try makeService()
        defer { try? FileManager.default.removeItem(at: dir) }
        let past = now.addingTimeInterval(-3600)
        #expect(try service.setPasswordRotationDate(account, date: past, now: now))
        // Semua jalur simpan (date != nil atau nil) tidak boleh menghapus.
        #expect(try service.setPasswordRotationDate(account, date: past, now: now) == false)
        #expect(try service.setPasswordRotationDate(account, date: nil, now: now) == false)
        #expect(account.passwordLastRotatedDate == past)
    }

    // 6. Storage FAILED menolak penghapusan; data utuh.
    @Test("Storage FAILED blocks explicit delete")
    @MainActor
    func testStorageFailedBlocksDelete() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault_retention_fail_\\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = dir.appendingPathComponent("corrupt.sqlite")
        try Data("CORRUPT".utf8).write(to: db)
        let coordinator = StorageCoordinator(storeURL: db)
        _ = coordinator.bootstrap()
        let context = ModelContext(coordinator.presentedContainer!)
        let service = VaultDataService(modelContext: context, storageGate: coordinator)
        let account = Account(name: "Dummy", platform: "YouTube")
        account.passwordLastRotatedDate = now.addingTimeInterval(-3600)
        context.insert(account)
        #expect(throws: VaultError.self) { try service.removePasswordRotationDate(account) }
        #expect(account.passwordLastRotatedDate != nil)
    }

    // 7. Invalid future date tidak memutasi model.
    @Test("Invalid future date does not mutate model")
    @MainActor
    func testFutureNoMutation() throws {
        let (service, account, dir) = try makeService()
        defer { try? FileManager.default.removeItem(at: dir) }
        let past = now.addingTimeInterval(-3600)
        #expect(try service.setPasswordRotationDate(account, date: past, now: now))
        #expect(throws: VaultError.self) {
            try service.setPasswordRotationDate(account, date: now.addingTimeInterval(3600), now: now)
        }
        #expect(account.passwordLastRotatedDate == past)
    }

    // 8. Nil tetap diperbolehkan untuk data baru (tidak ada tanggal).
    @Test("Nil allowed for new accounts without rotation")
    @MainActor
    func testNilAllowedForNew() throws {
        let (_, account, dir) = try makeService()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(account.passwordLastRotatedDate == nil)
        if case .valid = MetadataValidator().validatePasswordRotationDate(nil, now: now) {} else {
            Issue.record("nil harus valid")
        }
    }

    // 9. Logging tidak memuat informasi sensitif.
    @Test("Activity log stays generic on write and delete")
    @MainActor
    func testLogGeneric() throws {
        let (service, account, dir) = try makeService()
        defer { try? FileManager.default.removeItem(at: dir) }
        let past = now.addingTimeInterval(-3600)
        _ = try service.setPasswordRotationDate(account, date: past, now: now)
        _ = try service.removePasswordRotationDate(account)
        for log in try service.fetchActivityLogs(for: account) {
            #expect(!log.details.contains(account.name))
            #expect(!log.details.contains("1760000000"))
            #expect(!log.details.contains("password"))
        }
    }

    // 10. Data historis lama utuh saat editor dibuka dan disimpan tanpa perubahan.
    @Test("Historical data intact when reopened and saved unchanged")
    @MainActor
    func testReopenSaveUnchanged() throws {
        let (service, account, dir) = try makeService()
        defer { try? FileManager.default.removeItem(at: dir) }
        let past = now.addingTimeInterval(-86_400 * 7)
        #expect(try service.setPasswordRotationDate(account, date: past, now: now))
        // Simulasi reopen: editor membaca nilai model (rotationEnabled = date != nil),
        // lalu Save dengan toggle ON & tanggal yang sama -> idempotent, nilai identik.
        let reopenedDate = account.passwordLastRotatedDate ?? Date()
        #expect(try service.setPasswordRotationDate(account, date: reopenedDate, now: now) == false)
        #expect(account.passwordLastRotatedDate == past)
        // Dan toggle OFF pun tidak mengubahnya.
        #expect(try service.setPasswordRotationDate(account, date: nil, now: now) == false)
        #expect(account.passwordLastRotatedDate == past)
    }
}
