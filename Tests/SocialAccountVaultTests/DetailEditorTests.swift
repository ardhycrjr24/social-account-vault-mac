import Testing
import Foundation
import SwiftData
@testable import SocialAccountVaultCore

/// Task 4 — Account Detail Editor & Feature Integration regression tests.
/// Menguji jalur service/validator yang dipakai editor; data dummy & temporary DB.
@Suite("Account Detail Editor Integration")
struct DetailEditorTests {
    private let metadataValidator = MetadataValidator()
    private let urlValidator = URLSafetyValidator()

    @MainActor
    private func makeReadyService() throws -> (VaultDataService, Account, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault_editor_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = dir.appendingPathComponent("editor.sqlite")
        let coordinator = StorageCoordinator(storeURL: db)
        _ = coordinator.bootstrap()
        let context = ModelContext(coordinator.presentedContainer!)
        let service = VaultDataService(modelContext: context, storageGate: coordinator)
        let account = try service.createAccount(name: "Dummy", platform: "YouTube")
        return (service, account, dir)
    }

    // 1. Editor load (state awal dari account tersedia).
    @Test("1. Editor initial state loads from account")
    @MainActor
    func testEditorLoad() throws {
        let (_, account, dir) = try makeReadyService()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(account.recoveryEmailReference.isEmpty)
        #expect(account.twoFactorStatus == .unknown)
        #expect(account.deviceOS == .macOS)
    }

    // 2. Save valid detail.
    @Test("2. Valid detail saves through service")
    @MainActor
    func testSaveValidDetail() throws {
        let (service, account, dir) = try makeReadyService()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try service.setRecoveryEmail(account, value: "dummy@example.com")
        _ = try service.setRecoveryPhoneHint(account, value: "•••• 8899")
        try service.setTwoFactor(account: account, status: .enabled, method: .passkey)
        try service.setDeviceOS(account, os: .macOS)
        #expect(account.recoveryEmailReference == "dummy@example.com")
        #expect(account.twoFactorMethod == .passkey)
    }

    // 3. Invalid metadata tidak tersimpan.
    @Test("3. Invalid identifier is not persisted")
    @MainActor
    func testInvalidMetadataRejected() throws {
        let (service, account, dir) = try makeReadyService()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(throws: VaultError.self) {
            try service.setStandardMetadata(on: account, key: .youtubeChannelID, value: "BAD-ID")
        }
        #expect(account.details.isEmpty)
    }

    // 4. Recovery email validation.
    @Test("4. Recovery email validation")
    func testRecoveryEmail() {
        if case .invalid = metadataValidator.validateRecoveryEmail("bad") {} else {
            Issue.record("email invalid harus ditolak")
        }
        if case .valid = metadataValidator.validateRecoveryEmail("") {} else {
            Issue.record("email kosong boleh")
        }
    }

    // 5. Recovery phone validation.
    @Test("5. Recovery phone validation")
    func testPhone() {
        if case .invalid = metadataValidator.validateRecoveryPhoneHint("081234567890") {} else {
            Issue.record("nomor lengkap harus ditolak")
        }
        if case .valid = metadataValidator.validateRecoveryPhoneHint("•••• 8899") {} else {
            Issue.record("hint tersamar boleh")
        }
    }

    // 6. 2FA status + method (disabled -> none).
    @Test("6. 2FA status and method consistency")
    @MainActor
    func testTwoFactor() throws {
        let (service, account, dir) = try makeReadyService()
        defer { try? FileManager.default.removeItem(at: dir) }
        try service.setTwoFactor(account: account, status: .disabled, method: .none)
        #expect(account.twoFactorStatus == .disabled)
        #expect(account.twoFactorMethod == .none)
    }

    // 7. Device OS.
    @Test("7. Device OS via enum")
    @MainActor
    func testDeviceOS() throws {
        let (service, account, dir) = try makeReadyService()
        defer { try? FileManager.default.removeItem(at: dir) }
        try service.setDeviceOS(account, os: .windows)
        #expect(account.deviceOS == .windows)
        _ = try service.setDeviceName(account, value: "Workstation A")
        #expect(account.primaryDeviceName == "Workstation A")
    }

    // 8. Direct login URL.
    @Test("8. Direct login URL persists without opening")
    @MainActor
    func testDirectLogin() throws {
        let (service, account, dir) = try makeReadyService()
        defer { try? FileManager.default.removeItem(at: dir) }
        let decision = urlValidator.classify("https://youtube.com/login", platform: "YouTube",
                                              registry: .specificationExamples)
        #expect(decision.isOpenable)
        _ = try service.setDirectLoginURL(account, value: "https://youtube.com/login")
        #expect(account.directLoginURLString == "https://youtube.com/login")
    }

    // 9. URL warning confirmation decision.
    @Test("9. Warning URL requires confirmation decision")
    func testURLWarning() {
        let d = urlValidator.classify("https://unknown.test", platform: "YouTube")
        if case .warning(_, let host, let reasons) = d {
            #expect(!host.isEmpty)
            #expect(!reasons.isEmpty)
        } else { Issue.record("expected warning") }
    }

    // 10. URL blocked.
    @Test("10. Blocked URL cannot be stored")
    @MainActor
    func testURLBlocked() throws {
        let (service, account, dir) = try makeReadyService()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(throws: VaultError.self) {
            try service.setDirectLoginURL(account, value: "javascript:alert(1)")
        }
    }

    // 11. Metadata category consistency.
    @Test("11. Metadata category consistency")
    func testCategory() {
        if case .invalid = metadataValidator.validateCategory(key: .youtubeChannelID, expected: .monetization) {} else {
            Issue.record("mismatch harus invalid")
        }
    }

    // 12. Advisory UI data (VALID/UNKNOWN/INVALID/VALID reason).
    @Test("12. Advisory statuses carry reasons")
    func testAdvisory() {
        #expect(metadataValidator.validateIdentifier("UCabcdefghij1234567890XY", for: .youtubeChannelID).isAccepted)
        if case .unknown(let reason) = metadataValidator.validateIdentifier("x", for: .shopeePartnerID) {
            #expect(!reason.isEmpty)
        } else { Issue.record("unknown reason") }
        if case .invalid(let reason) = metadataValidator.validateIdentifier("x", for: .youtubeChannelID) {
            #expect(!reason.isEmpty)
        } else { Issue.record("invalid reason") }
    }

    // 13. Monetization metadata.
    @Test("13. Monetization metadata via validator")
    @MainActor
    func testMonetization() throws {
        let (service, account, dir) = try makeReadyService()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try service.setStandardMetadata(on: account, key: .payoutSchedule, value: "monthly", expectedCategory: .monetization)
        _ = try service.setStandardMetadata(on: account, key: .payoutCurrency, value: "USD", expectedCategory: .monetization)
        #expect(account.details.contains { $0.key == "monetization.payout.schedule" })
        #expect(account.details.contains { $0.key == "monetization.payout.currency" })
    }

    // 14. ActivityLog tidak membocorkan data sensitif.
    @Test("14. Activity logs contain no sensitive values")
    @MainActor
    func testLogsSanitized() throws {
        let (service, account, dir) = try makeReadyService()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try service.setRecoveryEmail(account, value: "dummy@example.com")
        _ = try service.setRecoveryPhoneHint(account, value: "•••• 8899")
        try service.setDeviceName(account, value: "Workstation A")
        _ = try service.setDirectLoginURL(account, value: "https://youtube.com/login?token=sensitive")
        for log in try service.fetchActivityLogs(for: account) {
            #expect(!log.details.contains("dummy@example.com"))
            #expect(!log.details.contains("8899"))
            #expect(!log.details.contains("token="))
        }
    }

    // 15. Storage FAILED memblokir penyimpanan.
    @Test("15. Storage FAILED blocks all editor writes")
    @MainActor
    func testStorageFailedBlocks() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault_editor_fail_\(UUID().uuidString)")
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
        #expect(throws: VaultError.self) { try service.setRecoveryEmail(account, value: "a@b.co") }
        #expect(throws: VaultError.self) { try service.setDeviceOS(account, os: .macOS) }
        #expect(throws: VaultError.self) { try service.setDirectLoginURL(account, value: "https://x.com") }
        #expect(throws: VaultError.self) { try service.setDeviceName(account, value: "x") }
    }

    // 16. Edit berulang tidak duplikasi.
    @Test("16. Repeated edits are idempotent where applicable")
    @MainActor
    func testRepeatedEdit() throws {
        let (service, account, dir) = try makeReadyService()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(try service.setDeviceName(account, value: "Same"))
        #expect(!(try service.setDeviceName(account, value: "Same")))
        _ = try service.setStandardMetadata(on: account, key: .youtubeChannelID, value: "UCabcdefghij1234567890XY")
        _ = try service.setStandardMetadata(on: account, key: .youtubeChannelID, value: "UCabcdefghij1234567890XY")
        let details = account.details.filter { $0.key == "platform.youtube.channel_id" }
        #expect(details.count == 1)
    }

    // 17. Data tetap ada setelah reopen.
    @Test("17. Data persists after reopen")
    @MainActor
    func testPersistenceAfterReopen() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault_editor_reopen_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = dir.appendingPathComponent("editor.sqlite")
        let c1 = StorageCoordinator(storeURL: db)
        _ = c1.bootstrap()
        let s1 = VaultDataService(modelContext: ModelContext(c1.presentedContainer!), storageGate: c1)
        let a1 = try s1.createAccount(name: "Dummy", platform: "YouTube")
        _ = try s1.setRecoveryEmail(a1, value: "dummy@example.com")
        try s1.setDeviceOS(a1, os: .linux)

        let c2 = StorageCoordinator(storeURL: db)
        _ = c2.bootstrap()
        let s2 = VaultDataService(modelContext: ModelContext(c2.presentedContainer!), storageGate: c2)
        let accounts = try s2.fetchActiveAccounts()
        #expect(accounts.count == 1)
        #expect(accounts.first?.recoveryEmailReference == "dummy@example.com")
        #expect(accounts.first?.deviceOS == .linux)
    }
}
