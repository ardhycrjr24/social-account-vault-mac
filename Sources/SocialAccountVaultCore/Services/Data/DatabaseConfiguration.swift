import Foundation
import SwiftData

/// Configures and manages the SwiftData persistence container backed by SQLite.
@MainActor
public final class DatabaseConfiguration: Sendable {
    public static let shared = DatabaseConfiguration()

    private init() {}

    /// Canonical schema definition for Social Account Vault.
    public static var schema: Schema {
        Schema([
            Account.self,
            PlatformCategory.self,
            AccountDetail.self,
            ActivityLog.self
        ])
    }

    /// Application Support directory dedicated to Social Account Vault storage.
    public static var defaultDatabaseDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("tech.anakterubuk.SocialAccountVault", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    /// Deterministic SQLite file URL in Application Support.
    public static var defaultDatabaseURL: URL {
        defaultDatabaseDirectory.appendingPathComponent("SocialAccountVault.sqlite")
    }

    /// Creates and configures a ModelContainer.
    ///
    /// - Parameters:
    ///   - url: Custom SQLite destination URL. If nil, uses default Application Support location.
    ///   - inMemory: Eksplisit opt-in untuk container ephemeral (hanya testing/preview/internal).
    ///     Jangan pernah dipanggil dengan `true` pada jalur produksi.
    /// - Returns: Fully initialized `ModelContainer`.
    ///
    /// - Warning: Metode ini TIDAK melakukan automatic in-memory fallback lagi. Jika
    ///   persistent store gagal dibuka, error dilempar. Gunakan
    ///   `openProductionContainer()` atau `openPersistentContainer(at:)` pada kode produksi.
    public static func createModelContainer(
        at url: URL? = nil,
        inMemory: Bool = false
    ) throws -> ModelContainer {
        if inMemory {
            return try makeEphemeralContainer(name: "SocialAccountVaultInMemory")
        }

        let storeURL = url ?? defaultDatabaseURL
        let configuration = ModelConfiguration(
            "SocialAccountVaultStore",
            schema: schema,
            url: storeURL,
            allowsSave: true
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Production safety: never substitute an in-memory store, never delete,
            // truncate, or recreate the on-disk database. Propagate a typed error so
            // callers can halt writes and show an explicit diagnostic state.
            throw VaultError.storageUnavailable(reason: "\(error)")
        }
    }

    /// Production entry point. Buka persistent store dan pastikan store benar-benar
    /// writable sebelum aplikasi mengizinkan operasi tulis apa pun.
    public static func openProductionContainer() throws -> ModelContainer {
        try openPersistentContainer(at: defaultDatabaseURL)
    }

    /// Membuka persistent store di URL tertentu (production atau test copy).
    /// File tidak pernah dihapus/dibuat ulang/dikosongkan pada kegagalan.
    public static func openPersistentContainer(at url: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "SocialAccountVaultStore",
            schema: schema,
            url: url,
            allowsSave: true
        )
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            throw VaultError.storageUnavailable(reason: "\(error)")
        }

        // Verifikasi store benar-benar persistent & writable. ModelContainer bisa saja
        // berhasil dibuat pada kondisi degradasi; kita harus menolaknya.
        guard let config = container.configurations.first,
              !config.isStoredInMemoryOnly else {
            throw VaultError.storageUnavailable(reason: "container is not backed by the requested persistent store")
        }
        return container
    }

    /// Jalur eksplisit satu-satunya untuk container ephemeral (testing/preview/internal).
    public static func makeEphemeralContainer(name: String = "SocialAccountVaultEphemeral") throws -> ModelContainer {
        let configuration = ModelConfiguration(
            name,
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Opens a store at `url` under the current Phase 4 schema, performing a
    /// SwiftData lightweight migration when the on-disk schema is older.
    ///
    /// Failure-handling contract (Phase 4 AC-MIG-4):
    /// - On failure this method THROWS `VaultError.migrationFailure`; it never
    ///   silently substitutes an in-memory store for the on-disk database.
    /// - The original SQLite file (and its WAL/SHM artifacts) is left untouched
    ///   on disk; this method performs no deletion, truncation, or recreation.
    /// - Callers must halt writes and surface an explicit error to the user.
    ///
    /// This is the safe, testable migration entry point. It is intentionally
    /// separate from `createModelContainer` so production boot behavior is not
    /// altered implicitly; migration callers opt in explicitly.
    ///
    /// - Parameter url: The SQLite store to open/migrate (must be a test copy or
    ///   an explicit user store; never the canonical test fixture).
    /// - Returns: A migrated, read-write `ModelContainer`.
    public static func createMigratedContainer(at url: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "SocialAccountVaultMigratedStore",
            schema: schema,
            url: url,
            allowsSave: true
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Preserve the original file: do NOT delete, truncate, or fall back
            // to an in-memory store. Surface an explicit, actionable error.
            throw VaultError.migrationFailure(reason: "\(error)")
        }
    }
}
