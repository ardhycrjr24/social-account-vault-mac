import Testing
import Foundation
import SwiftData
@testable import SocialAccountVaultCore

/// Task 2 — Service Validation & Metadata Integration regression tests.
/// Seluruh data bersifat dummy; tidak ada credential atau data akun sungguhan.
@Suite("Metadata & Recovery Validation")
struct MetadataValidationTests {

    private let validator = MetadataValidator()

    // 1. YouTube identifier valid/invalid.
    @Test("YouTube channel identifier validation")
    func testYouTubeIdentifier() {
        if case .valid = validator.validateIdentifier("UCabcdefghij1234567890XY", for: .youtubeChannelID) {
        } else { Issue.record("UC + 22 chars harus valid") }
        if case .invalid = validator.validateIdentifier("abc123", for: .youtubeChannelID) {
        } else { Issue.record("tanpa prefix UC harus invalid") }
        if case .invalid = validator.validateIdentifier("UC bad value!", for: .youtubeChannelID) {
        } else { Issue.record("karakter terlarang harus invalid") }
    }

    // 2. Google Publisher ID valid/invalid.
    @Test("AdSense publisher identifier validation")
    func testPublisherIdentifier() {
        if case .valid = validator.validateIdentifier("pub-1234567890", for: .adsensePublisherID) {
        } else { Issue.record("pub-... harus valid") }
        if case .invalid = validator.validateIdentifier("pub123", for: .adsensePublisherID) {
        } else { Issue.record("tanpa tanda hubung harus invalid") }
    }

    // 3. Identifier tidak dikenal -> unknown (tidak ditolak).
    @Test("Unknown identifier format is UNKNOWN, not rejected")
    func testUnknownIdentifier() {
        let result = validator.validateIdentifier("SOME-UNKNOWN-ID", for: .shopeePartnerID)
        if case .unknown = result {
            #expect(result.isAccepted)
        } else {
            Issue.record("format belum dikenal harus .unknown")
        }
    }

    // 4. Advisory detection: warning untuk panjang tidak lazim.
    @Test("Advisory WARNING with reason")
    func testAdvisoryWarning() {
        let result = validator.validateIdentifier("UCshort", for: .youtubeChannelID)
        if case .warning(let reason) = result {
            #expect(!reason.isEmpty)
            #expect(result.isAccepted)
        } else {
            Issue.record("UC terlalu pendek harus .warning")
        }
    }

    // 5. Recovery email valid/invalid.
    @Test("Recovery email format validation")
    func testRecoveryEmail() {
        if case .valid = validator.validateRecoveryEmail("dummy@example.com") {} else {
            Issue.record("email dummy valid harus diterima")
        }
        if case .invalid = validator.validateRecoveryEmail("not-an-email") {} else {
            Issue.record("email invalid harus ditolak")
        }
        if case .invalid = validator.validateRecoveryEmail("password@example.com") {} else {
            Issue.record("email mengandung kata terlarang harus ditolak")
        }
    }

    // 6. Recovery email kosong (opsional).
    @Test("Empty recovery email is accepted")
    func testEmptyRecoveryEmail() {
        if case .valid = validator.validateRecoveryEmail("") {} else {
            Issue.record("email kosong harus diterima (opsional)")
        }
    }

    // 7. Recovery phone masked/unmasked.
    @Test("Masked recovery phone enforcement")
    func testPhoneHint() {
        if case .valid = validator.validateRecoveryPhoneHint("•••• 8899") {} else {
            Issue.record("hint tersamar harus diterima")
        }
        if case .invalid = validator.validateRecoveryPhoneHint("081234567890") {} else {
            Issue.record("nomor lengkap harus ditolak")
        }
        if case .invalid = validator.validateRecoveryPhoneHint("8899") {} else {
            Issue.record("digit tanpa mask harus ditolak")
        }
    }

    // 8. Metadata key/category mismatch.
    @Test("Category mismatch is rejected")
    func testCategoryMismatch() {
        if case .invalid = validator.validateCategory(key: .youtubeChannelID, expected: .deviceContext) {} else {
            Issue.record("mismatch kategori harus ditolak")
        }
        if case .valid = validator.validateCategory(key: .youtubeChannelID, expected: .platformIdentifier) {} else {
            Issue.record("kategori cocok harus diterima")
        }
    }

    // Helper: buat service dengan storage READY pada DB sementara.
    @MainActor
    private func makeReadyService() throws -> (VaultDataService, Account, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault_meta_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = dir.appendingPathComponent("meta.sqlite")
        let coordinator = StorageCoordinator(storeURL: db)
        _ = coordinator.bootstrap()
        let context = ModelContext(coordinator.presentedContainer!)
        let service = VaultDataService(modelContext: context, storageGate: coordinator)
        let account = try service.createAccount(name: "Dummy", platform: "YouTube")
        return (service, account, dir)
    }

    // 9. Credential dilarang lolos lewat setStandardMetadata.
    @Test("Prohibited credentials are still blocked")
    @MainActor
    func testCredentialBlocked() throws {
        let (service, account, dir) = try makeReadyService()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(throws: VaultError.self) {
            try service.setStandardMetadata(on: account, key: .youtubeChannelID, value: "password123")
        }
    }

    // 10. Tidak ada sensitive data di activity log.
    @Test("No raw recovery email or phone in activity logs")
    @MainActor
    func testNoSensitiveDataInLogs() throws {
        let (service, account, dir) = try makeReadyService()
        defer { try? FileManager.default.removeItem(at: dir) }
        try service.setRecoveryEmail(account, value: "dummy.person@example.com")
        try service.setRecoveryPhoneHint(account, value: "•••• 8899")
        let logs = try service.fetchActivityLogs(for: account)
        for log in logs {
            #expect(!log.details.contains("dummy.person@example.com"))
            #expect(!log.details.contains("8899"))
        }
    }

    // 11. Storage FAILED tetap memblokir operasi tulis (Task 0 regression).
    @Test("All new write methods are blocked when storage FAILED")
    @MainActor
    func testWritesBlockedWhenFailed() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault_meta_fail_\(UUID().uuidString)")
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
        #expect(throws: VaultError.self) { try service.setRecoveryPhoneHint(account, value: "•••• 1234") }
        #expect(throws: VaultError.self) { try service.setTwoFactor(account: account, status: .enabled, method: .passkey) }
        #expect(throws: VaultError.self) { try service.setDeviceOS(account, os: .macOS) }
        #expect(throws: VaultError.self) { try service.setStandardMetadata(on: account, key: .youtubeChannelID, value: "UCabcdefghij1234567890XY") }
    }

    // 12. Typed metadata methods menyimpan nilai dengan benar saat READY.
    @Test("Typed metadata writes persist through service")
    @MainActor
    func testTypedMetadataWrites() throws {
        let (service, account, dir) = try makeReadyService()
        defer { try? FileManager.default.removeItem(at: dir) }
        try service.setRecoveryEmail(account, value: "dummy@example.com")
        try service.setRecoveryPhoneHint(account, value: "•••• 8899")
        try service.setTwoFactor(account: account, status: .enabled, method: .authenticatorApp)
        try service.setDeviceOS(account, os: .macOS)
        try service.setStandardMetadata(on: account, key: .youtubeChannelID, value: "UCabcdefghij1234567890XY")
        #expect(account.recoveryEmailReference == "dummy@example.com")
        #expect(account.recoveryPhoneHint == "•••• 8899")
        #expect(account.twoFactorStatus == .enabled)
        #expect(account.twoFactorMethod == .authenticatorApp)
        #expect(account.deviceOS == .macOS)
        #expect(account.details.contains { $0.key == StandardMetadataKey.youtubeChannelID.rawValue })
    }
}
