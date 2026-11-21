import Testing
import Foundation
import SwiftData
@testable import SocialAccountVaultCore

/// TASK 10.1 — Two-Factor combination enforcement tests.
/// Semua data dummy, database terisolasi, tanpa produksi.
@Suite("Two-Factor Combination Enforcement")
struct TwoFactorCombinationTests {

    private let validCombinations: [(TwoFactorStatus, TwoFactorMethod)] = [
        (.enabled, .authenticatorApp), (.enabled, .hardwareKey),
        (.enabled, .smsBackup), (.enabled, .passkey),
        (.disabled, .none),
        (.unknown, .none),
        (.enforcedByOrg, .none), (.enforcedByOrg, .authenticatorApp),
        (.enforcedByOrg, .hardwareKey), (.enforcedByOrg, .smsBackup),
        (.enforcedByOrg, .passkey),
    ]

    private let invalidCombinations: [(TwoFactorStatus, TwoFactorMethod)] = [
        (.enabled, .none),
        (.disabled, .authenticatorApp), (.disabled, .hardwareKey),
        (.disabled, .smsBackup), (.disabled, .passkey),
        (.unknown, .authenticatorApp), (.unknown, .hardwareKey),
        (.unknown, .smsBackup), (.unknown, .passkey),
    ]

    // 1. Semua kombinasi valid diterima (logika statis).
    @Test("All approved combinations are accepted")
    func testValidCombinationsAccepted() {
        for (status, method) in validCombinations {
            #expect(
                status.allows(method: method),
                "\(status)/\(method) harus valid"
            )
        }
    }

    // 2. Semua kombinasi invalid ditolak (logika statis).
    @Test("All disallowed combinations are rejected")
    func testInvalidCombinationsRejected() {
        for (status, method) in invalidCombinations {
            #expect(
                !status.allows(method: method),
                "\(status)/\(method) harus invalid"
            )
        }
    }

    @MainActor
    private func makeReadyService() throws -> (VaultDataService, Account, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault_2fa_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = dir.appendingPathComponent("2fa.sqlite")
        let coordinator = StorageCoordinator(storeURL: db)
        _ = coordinator.bootstrap()
        let context = ModelContext(coordinator.presentedContainer!)
        let service = VaultDataService(modelContext: context, storageGate: coordinator)
        let account = try service.createAccount(name: "Dummy", platform: "YouTube")
        return (service, account, dir)
    }

    // 3. Pemanggilan service langsung: valid tersimpan.
    @Test("Direct service calls persist valid combinations")
    @MainActor
    func testDirectServiceValid() throws {
        let (service, account, dir) = try makeReadyService()
        defer { try? FileManager.default.removeItem(at: dir) }
        for (status, method) in validCombinations {
            try service.setTwoFactor(account: account, status: status, method: method)
            #expect(account.twoFactorStatus == status)
            #expect(account.twoFactorMethod == method)
        }
    }

    // 4. Pemanggilan service langsung: invalid dilempar & tidak mengubah data.
    @Test("Direct service calls reject invalid combinations without mutation")
    @MainActor
    func testDirectServiceInvalidNoMutation() throws {
        let (service, account, dir) = try makeReadyService()
        defer { try? FileManager.default.removeItem(at: dir) }
        try service.setTwoFactor(account: account, status: .enabled, method: .passkey)
        let beforeStatus = account.twoFactorStatus
        let beforeMethod = account.twoFactorMethod

        for (status, method) in invalidCombinations {
            #expect(throws: VaultError.self) {
                try service.setTwoFactor(account: account, status: status, method: method)
            }
            #expect(account.twoFactorStatus == beforeStatus, "status tidak boleh berubah saat validasi gagal")
            #expect(account.twoFactorMethod == beforeMethod, "method tidak boleh berubah saat validasi gagal")
        }
    }

    // 5. Storage FAILED tetap menolak (guardWritable sebelum validasi kombinasi).
    @Test("Storage FAILED rejects writes even for valid combinations")
    @MainActor
    func testStorageFailedStillBlocks() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault_2fa_fail_\(UUID().uuidString)")
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
            try service.setTwoFactor(account: account, status: .enabled, method: .passkey)
        }
    }

    // 6. Data lama tidak berubah hanya karena validasi baru (dibaca, bukan ditulis).
    @Test("Legacy stored combinations are not mutated by new validation")
    @MainActor
    func testLegacyDataUntouched() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault_2fa_legacy_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = dir.appendingPathComponent("legacy.sqlite")
        let coordinator = StorageCoordinator(storeURL: db)
        _ = coordinator.bootstrap()
        let context = ModelContext(coordinator.presentedContainer!)

        // Simulasikan data lama: enabled + none (sekarang invalid) ditulis langsung
        // ke model, sebagaimana aplikasi lama menyimpannya.
        let legacy = Account(name: "Legacy", platform: "YouTube")
        legacy.twoFactorStatus = .enabled
        legacy.twoFactorMethod = .none
        context.insert(legacy)
        try context.save()

        #expect(legacy.twoFactorStatus == .enabled)
        #expect(legacy.twoFactorMethod == .none)
        // Validasi baru hanya aktif saat pemanggilan service, bukan mengubah data lama.
        #expect(!TwoFactorStatus.enabled.allows(method: .none))
    }

    // 7. Error tidak mengandung data sensitif.
    @Test("Validation error contains no sensitive account data")
    @MainActor
    func testErrorHasNoSensitiveData() throws {
        let (service, account, dir) = try makeReadyService()
        defer { try? FileManager.default.removeItem(at: dir) }
        do {
            try service.setTwoFactor(account: account, status: .disabled, method: .passkey)
            Issue.record("expected throw")
        } catch let error as VaultError {
            guard case .invalidTwoFactorCombination(let status, let method) = error else {
                Issue.record("unexpected error: \(error)"); return
            }
            // Hanya berisi nama status/metode enum, bukan nama akun/email/URL.
            let text = "\(status) \(method) \(error.localizedDescription)"
            #expect(!text.contains(account.name))
            #expect(!text.contains("dummy@example.com"))
            #expect(!text.contains("https://"))
        }
    }
}
