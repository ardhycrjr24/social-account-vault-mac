import Testing
import Foundation
import SwiftData
@testable import SocialAccountVaultCore

/// TASK 10.4 — passwordLastRotatedDate validation tests.
@Suite("Password Rotation Date Validation")
struct PasswordRotationDateTests {
    private let validator = MetadataValidator()
    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    @MainActor
    private func makeService() throws -> (VaultDataService, Account, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault_rotation_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = dir.appendingPathComponent("rotation.sqlite")
        let coordinator = StorageCoordinator(storeURL: db)
        _ = coordinator.bootstrap()
        let context = ModelContext(coordinator.presentedContainer!)
        let service = VaultDataService(modelContext: context, storageGate: coordinator)
        let account = try service.createAccount(name: "Dummy", platform: "YouTube")
        return (service, account, dir)
    }

    // Tanggal masa depan ditolak validator bersama.
    @Test("Future rotation date is rejected")
    func testFutureRejected() {
        let result = validator.validatePasswordRotationDate(now.addingTimeInterval(3600), now: now)
        if case .invalid = result {} else { Issue.record("future date harus invalid") }
    }

    // Tanggal valid & nil diterima.
    @Test("Past date and nil are accepted")
    func testValidAndNil() {
        if case .valid = validator.validatePasswordRotationDate(now.addingTimeInterval(-86_400), now: now) {} else {
            Issue.record("past date harus valid")
        }
        if case .valid = validator.validatePasswordRotationDate(nil, now: now) {} else {
            Issue.record("nil harus valid")
        }
    }

    // Direct service call: tanggal valid tersimpan.
    @Test("Direct service call persists valid date")
    @MainActor
    func testDirectServiceValid() throws {
        let (service, account, dir) = try makeService()
        defer { try? FileManager.default.removeItem(at: dir) }
        let past = now.addingTimeInterval(-3600)
        #expect(try service.setPasswordRotationDate(account, date: past, now: now))
        #expect(account.passwordLastRotatedDate == past)
    }

    // Direct service call: masa depan ditolak & tidak mutasi.
    @Test("Direct service call rejects future date without mutation")
    @MainActor
    func testDirectServiceFutureNoMutation() throws {
        let (service, account, dir) = try makeService()
        defer { try? FileManager.default.removeItem(at: dir) }
        let past = now.addingTimeInterval(-3600)
        _ = try service.setPasswordRotationDate(account, date: past, now: now)
        let before = account.passwordLastRotatedDate
        #expect(throws: VaultError.self) {
            try service.setPasswordRotationDate(account, date: now.addingTimeInterval(3600), now: now)
        }
        #expect(account.passwordLastRotatedDate == before)
    }

    // Idempotent.
    @Test("Repeated identical write is idempotent")
    @MainActor
    func testIdempotent() throws {
        let (service, account, dir) = try makeService()
        defer { try? FileManager.default.removeItem(at: dir) }
        let past = now.addingTimeInterval(-3600)
        #expect(try service.setPasswordRotationDate(account, date: past, now: now))
        #expect(!(try service.setPasswordRotationDate(account, date: past, now: now)))
    }

    // Storage FAILED menolak.
    @Test("Storage FAILED blocks write")
    @MainActor
    func testStorageFailed() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault_rotation_fail_\(UUID().uuidString)")
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
        #expect(throws: VaultError.self) {
            try service.setPasswordRotationDate(account, date: now.addingTimeInterval(-3600), now: now)
        }
    }

    // Error tidak mengandung data sensitif.
    @Test("Error message contains no sensitive data")
    @MainActor
    func testErrorSanitized() throws {
        let (service, account, dir) = try makeService()
        defer { try? FileManager.default.removeItem(at: dir) }
        do {
            try service.setPasswordRotationDate(account, date: now.addingTimeInterval(3600), now: now)
            Issue.record("expected throw")
        } catch {
            let text = error.localizedDescription
            #expect(!text.contains(account.name))
            #expect(!text.contains("dummy@example.com"))
            #expect(!text.contains("password123"))
        }
    }

    // Log generik tidak membocorkan tanggal/akun.
    @Test("Activity log stays generic")
    @MainActor
    func testLogGeneric() throws {
        let (service, account, dir) = try makeService()
        defer { try? FileManager.default.removeItem(at: dir) }
        let past = now.addingTimeInterval(-3600)
        _ = try service.setPasswordRotationDate(account, date: past, now: now)
        for log in try service.fetchActivityLogs(for: account) {
            #expect(!log.details.contains(account.name))
            #expect(!log.details.contains("1760000000"))
        }
    }
}
