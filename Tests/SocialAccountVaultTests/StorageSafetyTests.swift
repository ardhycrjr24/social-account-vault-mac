import Testing
import Foundation
import SwiftData
import CryptoKit
@testable import SocialAccountVaultCore

/// Task 0 — Production Storage Safety regression tests.
///
/// Semua test memakai temporary directory dan database khusus pengujian.
/// TIDAK pernah membuka atau menguji database produksi.
@Suite("Production Storage Safety")
struct StorageSafetyTests {

    private static func tempDir(_ tag: String = #function) throws -> URL {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(
            "vault_storage_safety_\(tag)_\(UUID().uuidString)"
        )
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func sha256(of path: String) throws -> String {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let digest = Data(SHA256.hash(data: data))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // 1. Persistent container berhasil dibuka.
    @Test("1. Persistent container opens and is reported READY")
    @MainActor
    func testPersistentContainerOpensReady() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = dir.appendingPathComponent("healthy.sqlite")

        let coordinator = StorageCoordinator(storeURL: db)
        #expect(coordinator.bootstrap(), "bootstrap harus berhasil pada DB sehat")
        #expect(coordinator.status == .ready)
        #expect(coordinator.container != nil)
        #expect(coordinator.status.isWritable)

        // File SQLite nyata harus dibuat di lokasi yang diminta.
        #expect(FileManager.default.fileExists(atPath: db.path), "file SQLite harus dibuat")
    }

    // 2 & 3. Kegagalan tidak membuat automatic in-memory fallback.
    @Test("2-3. Corrupt persistent store fails without silent in-memory fallback")
    @MainActor
    func testFailureHasNoAutomaticInMemoryFallback() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = dir.appendingPathComponent("corrupt.sqlite")
        let garbage = Data("NOT A SQLITE DATABASE — CORRUPT HEADER".utf8)
        try garbage.write(to: db)

        let coordinator = StorageCoordinator(storeURL: db)
        #expect(!coordinator.bootstrap(), "bootstrap harus gagal pada DB korup")
        guard case .failed = coordinator.status else {
            Issue.record("Status harus FAILED, bukan \(coordinator.status)")
            return
        }
        #expect(!coordinator.status.isWritable)
        #expect(coordinator.container == nil, "container produksi harus nil saat FAILED")

        // Container yang dipasang ke UI adalah container diagnostik EKSPLISIT,
        // bukan pengganti diam-diam dari store produksi.
        #expect(coordinator.diagnosticContainer != nil)
        #expect(coordinator.container == nil)
    }

    // 4. Write operation ditolak ketika storage FAILED (langsung di service).
    @Test("4. All service writes are rejected while storage FAILED")
    @MainActor
    func testWritesRejectedWhenStorageFailed() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = dir.appendingPathComponent("corrupt.sqlite")
        try Data("CORRUPT".utf8).write(to: db)

        let coordinator = StorageCoordinator(storeURL: db)
        #expect(!coordinator.bootstrap())

        // Service dipanggil LANGSUNG (bukan lewat UI), memakai context diagnostik.
        let context = ModelContext(coordinator.diagnosticContainer!)
        let service = VaultDataService(modelContext: context, storageGate: coordinator)

        #expect(throws: VaultError.self) {
            try service.createAccount(name: "Should Fail", platform: "YouTube")
        }

        // Operasi tulis lain juga harus ditolak. Buat akun di context diagnostic
        // tanpa gate untuk dipakai sebagai target mutate.
        let account = Account(name: "Target", platform: "YouTube")
        context.insert(account)

        #expect(throws: VaultError.self) { try service.updateAccount(account, name: "x", username: "", emailReference: "", profileURLString: "", officialDashboardURLString: "", accountType: .personal, accountStatus: .active, monetizationStatus: .notMonetized, notes: "") }
        #expect(throws: VaultError.self) { try service.archiveAccount(account) }
        #expect(throws: VaultError.self) { try service.restoreAccount(account) }
        #expect(throws: VaultError.self) { try service.deleteAccount(account) }
        #expect(throws: VaultError.self) { try service.markChecked(account) }
        #expect(throws: VaultError.self) { try service.addDetail(to: account, key: "platform.youtube.channel_id", value: "UC123") }
        #expect(throws: VaultError.self) { try service.reassignCategory(account: account, to: nil) }
    }

    // 5. Read-only/test container hanya dibuat lewat jalur eksplisit.
    @Test("5. In-memory container is created only via explicit path")
    @MainActor
    func testInMemoryOnlyViaExplicitPath() throws {
        let explicit = try DatabaseConfiguration.makeEphemeralContainer(name: "ExplicitTest")
        #expect(explicit.configurations.first?.isStoredInMemoryOnly == true)

        let viaParameter = try DatabaseConfiguration.createModelContainer(inMemory: true)
        #expect(viaParameter.configurations.first?.isStoredInMemoryOnly == true)

        // Jalur persistent (inMemory: false) TIDAK boleh menghasilkan in-memory.
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = dir.appendingPathComponent("disk.sqlite")
        let disk = try DatabaseConfiguration.createModelContainer(at: db, inMemory: false)
        #expect(disk.configurations.first?.isStoredInMemoryOnly == false)
    }

    // 6. Database asli tetap utuh setelah kegagalan.
    @Test("6. Original database file is byte-identical after failure")
    @MainActor
    func testOriginalFilePreservedAfterFailure() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = dir.appendingPathComponent("corrupt.sqlite")
        let garbage = Data("PRESERVE-ME-CORRUPT-DATA".utf8)
        try garbage.write(to: db)
        let before = try Self.sha256(of: db.path)

        let coordinator = StorageCoordinator(storeURL: db)
        #expect(!coordinator.bootstrap())
        #expect(!coordinator.retry())

        #expect(FileManager.default.fileExists(atPath: db.path))
        let after = try Self.sha256(of: db.path)
        #expect(before == after, "file korup harus tetap byte-identik setelah gagal/retry")
    }

    // 7. Recovery berhasil setelah masalah diperbaiki.
    @Test("7. Retry succeeds only after persistent store is genuinely openable")
    @MainActor
    func testRecoveryAfterProblemFixed() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = dir.appendingPathComponent("recover.sqlite")
        try Data("CORRUPT".utf8).write(to: db)

        let coordinator = StorageCoordinator(storeURL: db)
        #expect(!coordinator.bootstrap())
        #expect(coordinator.container == nil)

        // Perbaiki masalah: hapus file korup di temp (BUKAN produksi) agar
        // coordinator membuka ulang path yang sama menjadi DB sehat.
        try FileManager.default.removeItem(at: db)
        #expect(coordinator.retry(), "retry harus berhasil setelah file dibersihkan")
        #expect(coordinator.status == .ready)
        #expect(coordinator.container != nil)
        #expect(coordinator.status.isWritable)

        // Setelah pulih, tulis lewat service harus berjalan normal.
        let context = ModelContext(coordinator.container!)
        let service = VaultDataService(modelContext: context, storageGate: coordinator)
        let account = try service.createAccount(name: "Recovered", platform: "YouTube")
        #expect(account.name == "Recovered")
    }

    // 8. Tidak ada regresi migration tests (smoke: migrasi fixture kanonik tetap aman).
    @Test("8. V1 migration path remains unaffected by storage hardening")
    @MainActor
    func testMigrationPathStillWorks() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let copy = dir.appendingPathComponent("migration_copy.sqlite")

        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/SocialAccountVaultTests
            .deletingLastPathComponent() // Tests
            .appendingPathComponent("Fixtures/v1_migration_fixture.sqlite")
        #expect(FileManager.default.fileExists(atPath: fixture.path))
        try FileManager.default.copyItem(at: fixture, to: copy)

        let migrated = try DatabaseConfiguration.createMigratedContainer(at: copy)
        #expect(migrated.configurations.first?.isStoredInMemoryOnly == false)

        // Failure path migrasi tetap melempar, bukan fallback.
        let corrupt = dir.appendingPathComponent("corrupt.sqlite")
        try Data("CORRUPT".utf8).write(to: corrupt)
        #expect(throws: VaultError.self) {
            _ = try DatabaseConfiguration.createMigratedContainer(at: corrupt)
        }
    }
}
