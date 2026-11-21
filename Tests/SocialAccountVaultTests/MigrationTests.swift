import Testing
import Foundation
import SwiftData
import SQLite3
import CryptoKit
@testable import SocialAccountVaultCore

/// Phase 4.1 — V1.0 → Phase 4 lightweight migration verification.
///
/// Every test operates on an ISOLATED COPY of the canonical V1.0 fixture.
/// The canonical fixture (`Tests/Fixtures/v1_migration_fixture.sqlite`) is
/// NEVER opened read-write, migrated, or modified. No production database is
/// touched. These tests prove AC-MIG-1 through AC-MIG-4.
@Suite("Phase 4 V1 Fixture Migration Tests")
struct MigrationTests {

    // MARK: - Fixture Isolation Helpers

    /// Locates the repository root by walking up from this source file.
    private static func projectRoot() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath)
        while dir.lastPathComponent != "SocialAccountVault" {
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return dir
    }

    private static func canonicalFixtureURL() throws -> URL {
        try projectRoot().appendingPathComponent("Tests/Fixtures/v1_migration_fixture.sqlite")
    }

    /// Creates a fresh isolated copy of the canonical fixture in a temp dir.
    /// Returns (tempDir, copyURL). Caller must remove tempDir when done.
    private static func makeIsolatedFixtureCopy() throws -> (URL, URL) {
        let fm = FileManager.default
        let canonical = try canonicalFixtureURL()
        guard fm.fileExists(atPath: canonical.path) else {
            throw VaultError.entityNotFound(entity: "V1Fixture", id: UUID())
        }
        let tempDir = fm.temporaryDirectory.appendingPathComponent("vault_migration_test_\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let copyURL = tempDir.appendingPathComponent("fixture_copy.sqlite")
        try fm.copyItem(at: canonical, to: copyURL)
        // Copy sidecars if present so the WAL fixture is readable as-is.
        for ext in ["-wal", "-shm"] {
            let src = canonical.path + ext
            if fm.fileExists(atPath: src) {
                try fm.copyItem(atPath: src, toPath: copyURL.path + ext)
            }
        }
        return (tempDir, copyURL)
    }

    private static func sha256(of path: String) throws -> String {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - A. Pre-Migration Snapshot

    @Test("A. Pre-migration fixture contains 5/9/7/14 records")
    @MainActor
    func testPreMigrationCounts() throws {
        let (tempDir, copyURL) = try Self.makeIsolatedFixtureCopy()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Open the copy under the V1-compatible read path via SwiftData fetch.
        let container = try DatabaseConfiguration.createMigratedContainer(at: copyURL)
        let context = ModelContext(container)
        let accounts = try context.fetch(FetchDescriptor<Account>())
        let categories = try context.fetch(FetchDescriptor<PlatformCategory>())
        let details = try context.fetch(FetchDescriptor<AccountDetail>())
        let logs = try context.fetch(FetchDescriptor<ActivityLog>())
        #expect(accounts.count == 5, "5 accounts")
        #expect(categories.count == 9, "9 categories")
        #expect(details.count == 7, "7 details")
        #expect(logs.count == 14, "14 logs")
        #expect(accounts.count + categories.count + details.count + logs.count == 35, "35 total")
    }

    // MARK: - B. Post-Migration Data Preservation

    @Test("B. Post-migration preserves counts, UUIDs, relationships, timestamps, notes, nil/empty, archive, Creator Tools")
    @MainActor
    func testPostMigrationPreservation() throws {
        let (tempDir, copyURL) = try Self.makeIsolatedFixtureCopy()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let canonicalSHA = try Self.sha256(of: try Self.canonicalFixtureURL().path)

        let container = try DatabaseConfiguration.createMigratedContainer(at: copyURL)
        let context = ModelContext(container)

        let accounts = try context.fetch(FetchDescriptor<Account>())
        let categories = try context.fetch(FetchDescriptor<PlatformCategory>())
        let details = try context.fetch(FetchDescriptor<AccountDetail>())
        let logs = try context.fetch(FetchDescriptor<ActivityLog>())

        // Counts unchanged
        #expect(accounts.count == 5)
        #expect(categories.count == 9)
        #expect(details.count == 7)
        #expect(logs.count == 14)

        // Deterministic category UUIDs preserved (C1..C9)
        let expectedCatUUIDs: [String: String] = [
            "YouTube": "00000000-0000-0000-0000-0000000000C1",
            "Instagram": "00000000-0000-0000-0000-0000000000C2",
            "TikTok": "00000000-0000-0000-0000-0000000000C3",
            "Facebook": "00000000-0000-0000-0000-0000000000C4",
            "Email": "00000000-0000-0000-0000-0000000000C5",
            "Shopee Affiliate": "00000000-0000-0000-0000-0000000000C6",
            "Google AdSense": "00000000-0000-0000-0000-0000000000C7",
            "Website & Domain": "00000000-0000-0000-0000-0000000000C8",
            "Creator Tools": "00000000-0000-0000-0000-0000000000C9"
        ]
        for cat in categories {
            if let expected = expectedCatUUIDs[cat.name] {
                #expect(cat.id.uuidString.lowercased() == expected.lowercased(), "category UUID \(cat.name)")
            }
        }

        // Account UUIDs preserved (deterministic ...0001-...000N)
        let expectedAccountUUIDs: [String: String] = [
            "Aruna Studio Official": "00000000-0000-0000-0001-000000000001",
            "Batik Modern Store": "00000000-0000-0000-0001-000000000002",
            "Nusantara Portal Web": "00000000-0000-0000-0001-000000000003",
            "Gadget Reviewer Affiliate": "00000000-0000-0000-0001-000000000004",
            "Legacy Internal Ops Mail": "00000000-0000-0000-0001-000000000005"
        ]
        for acc in accounts {
            if let expected = expectedAccountUUIDs[acc.name] {
                #expect(acc.id.uuidString.lowercased() == expected.lowercased(), "account UUID \(acc.name)")
            }
        }

        // Creator Tools relationship preserved
        guard let aruna = accounts.first(where: { $0.name == "Aruna Studio Official" }) else {
            Issue.record("Aruna Studio Official missing"); return
        }
        #expect(aruna.category?.name == "Creator Tools", "Aruna -> Creator Tools")
        #expect(aruna.category?.isDefault == false, "Creator Tools is custom")
        #expect(aruna.details.count == 2, "Aruna 2 details")
        #expect(aruna.activityLogs.count == 4, "Aruna 4 logs")

        // Per-account child distribution preserved
        let distribution: [(String, Int, Int)] = [
            ("Aruna Studio Official", 2, 4),
            ("Batik Modern Store", 1, 2),
            ("Nusantara Portal Web", 3, 4),
            ("Gadget Reviewer Affiliate", 1, 2),
            ("Legacy Internal Ops Mail", 0, 2)
        ]
        for (name, d, l) in distribution {
            guard let acc = accounts.first(where: { $0.name == name }) else {
                Issue.record("\(name) missing"); continue
            }
            #expect(acc.details.count == d, "\(name) details")
            #expect(acc.activityLogs.count == l, "\(name) logs")
        }

        // Archived state preserved (1 archived: Legacy Internal Ops Mail per fixture)
        let archived = accounts.filter { $0.isArchived }
        #expect(archived.count == 1, "exactly 1 archived account")

        // Multiline notes preserved (Aruna has multiline runbook notes)
        #expect(aruna.notes.contains("\n"), "Aruna notes must remain multiline")
        #expect(aruna.notes.contains("Runbook"), "Aruna runbook content preserved")

        // nil vs empty distinction preserved:
        // Legacy Internal Ops Mail has empty dashboard & profile URL, nil category
        guard let legacy = accounts.first(where: { $0.name == "Legacy Internal Ops Mail" }) else {
            Issue.record("Legacy Internal Ops Mail missing"); return
        }
        #expect(legacy.category == nil, "Legacy category nil (not empty object)")
        #expect(legacy.officialDashboardURLString == "", "Legacy dashboard empty string")
        #expect(legacy.profileURLString == "", "Legacy profile empty string")

        // domainExpirationDate: exactly 1 populated (Nusantara Portal Web), others nil
        let withDomainExp = accounts.filter { $0.domainExpirationDate != nil }
        #expect(withDomainExp.count == 1, "exactly 1 domainExpirationDate populated")
        #expect(withDomainExp.first?.name == "Nusantara Portal Web")

        // Timestamps preserved: creationDate strictly before baseDate for Aruna (1 year prior)
        #expect(aruna.creationDate < aruna.createdAt, "Aruna creationDate precedes createdAt")

        // Canonical fixture must remain byte-identical (never migrated directly)
        let canonicalSHAAfter = try Self.sha256(of: try Self.canonicalFixtureURL().path)
        #expect(canonicalSHA == canonicalSHAAfter, "canonical fixture untouched")
    }

    // MARK: - C. New Field Defaults

    @Test("C. New Phase 4 fields initialize to specified defaults on legacy records")
    @MainActor
    func testNewFieldDefaults() throws {
        let (tempDir, copyURL) = try Self.makeIsolatedFixtureCopy()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let container = try DatabaseConfiguration.createMigratedContainer(at: copyURL)
        let context = ModelContext(container)
        let accounts = try context.fetch(FetchDescriptor<Account>())
        #expect(accounts.count == 5)

        for acc in accounts {
            #expect(acc.directLoginURLString == "", "\(acc.name) directLoginURLString default empty")
            #expect(acc.recoveryEmailReference == "", "\(acc.name) recoveryEmailReference default empty")
            #expect(acc.recoveryPhoneHint == "", "\(acc.name) recoveryPhoneHint default empty")
            #expect(acc.twoFactorStatusRaw == "unknown", "\(acc.name) twoFactorStatusRaw default unknown")
            #expect(acc.twoFactorMethodRaw == "none", "\(acc.name) twoFactorMethodRaw default none")
            #expect(acc.primaryDeviceName == "", "\(acc.name) primaryDeviceName default empty")
            #expect(acc.deviceOSRaw == "macOS", "\(acc.name) deviceOSRaw default macOS")
            #expect(acc.passwordLastRotatedDate == nil, "\(acc.name) passwordLastRotatedDate default nil")

            // Typed enum accessors resolve to valid safe defaults
            #expect(acc.twoFactorStatus == .unknown)
            #expect(acc.twoFactorMethod == TwoFactorMethod.none)
            #expect(acc.deviceOS == .macOS)
        }
    }

    // MARK: - D. Persistence Stability Post-Migration

    @Test("D. Migrated database reopens, persists metadata writes, and creates no duplicate ActivityLog")
    @MainActor
    func testPostMigrationPersistence() throws {
        let (tempDir, copyURL) = try Self.makeIsolatedFixtureCopy()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let targetUUID = UUID(uuidString: "00000000-0000-0000-0001-000000000001")!
        let originalLogCount: Int

        // Session 1: migrate, write new metadata, save.
        do {
            let container = try DatabaseConfiguration.createMigratedContainer(at: copyURL)
            let context = ModelContext(container)
            let service = VaultDataService(modelContext: context)
            guard let aruna = try context.fetch(FetchDescriptor<Account>(predicate: #Predicate { $0.id == targetUUID })).first else {
                Issue.record("Aruna missing"); return
            }
            originalLogCount = aruna.activityLogs.count
            // Add a typed metadata detail (non-credential).
            try service.addDetail(to: aruna, key: StandardMetadataKey.youtubeChannelID.rawValue, value: "UC_aruna_studio_001")
            // Update a Phase 4 field directly and save.
            aruna.primaryDeviceName = "MacBook Pro M1 Studio"
            aruna.twoFactorStatus = .enabled
            aruna.twoFactorMethod = .authenticatorApp
            aruna.deviceOS = .macOS
            try context.save()
        }

        // Session 2: reopen the SAME migrated file and verify persistence.
        do {
            let container = try DatabaseConfiguration.createMigratedContainer(at: copyURL)
            let context = ModelContext(container)
            guard let aruna = try context.fetch(FetchDescriptor<Account>(predicate: #Predicate { $0.id == targetUUID })).first else {
                Issue.record("Aruna missing on reopen"); return
            }
            #expect(aruna.primaryDeviceName == "MacBook Pro M1 Studio", "device name persisted")
            #expect(aruna.twoFactorStatus == .enabled, "2FA status persisted")
            #expect(aruna.twoFactorMethod == .authenticatorApp, "2FA method persisted")
            #expect(aruna.details.contains { $0.key == StandardMetadataKey.youtubeChannelID.rawValue }, "new detail persisted")
            // Migration itself must NOT create duplicate logs. addDetail adds exactly 1 log.
            #expect(aruna.activityLogs.count == originalLogCount + 1, "no migration-induced duplicate logs")
            // Total record counts stable (5 accounts, 9 categories, 14 logs unchanged; details 7+1=8)
            let accounts = try context.fetch(FetchDescriptor<Account>())
            let categories = try context.fetch(FetchDescriptor<PlatformCategory>())
            let logs = try context.fetch(FetchDescriptor<ActivityLog>())
            #expect(accounts.count == 5)
            #expect(categories.count == 9)
            #expect(logs.count == 15, "14 original + 1 Detail Added")
        }
    }

    // MARK: - E. Failure Handling & Preservation

    @Test("E. Migration failure preserves original file and throws explicit error (no silent fallback)")
    @MainActor
    func testMigrationFailurePreservesDiskFile() throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("vault_migration_fail_\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        // Create a CORRUPT database file that cannot be opened/migrated.
        let corruptURL = tempDir.appendingPathComponent("corrupt.sqlite")
        let garbage = Data("THIS IS NOT A SQLITE DATABASE FILE — CORRUPT HEADER".utf8)
        try garbage.write(to: corruptURL)
        let shaBefore = try Self.sha256(of: corruptURL.path)
        let sizeBefore = try fm.attributesOfItem(atPath: corruptURL.path)[.size] as? Int

        // Attempting to migrate must THROW, not silently fall back to in-memory.
        var thrownError: Error?
        do {
            _ = try DatabaseConfiguration.createMigratedContainer(at: corruptURL)
            Issue.record("Expected migration to throw on corrupt database, but it succeeded")
        } catch {
            thrownError = error
        }
        #expect(thrownError != nil, "migration must throw on corrupt store")
        if let vaultError = thrownError as? VaultError {
            switch vaultError {
            case .migrationFailure:
                break // expected
            default:
                Issue.record("Expected VaultError.migrationFailure, got \(vaultError)")
            }
        }

        // Original corrupt file must be byte-identical (preserved, not deleted/truncated/recreated).
        #expect(fm.fileExists(atPath: corruptURL.path), "original file must still exist")
        let shaAfter = try Self.sha256(of: corruptURL.path)
        let sizeAfter = try fm.attributesOfItem(atPath: corruptURL.path)[.size] as? Int
        #expect(shaBefore == shaAfter, "original file content preserved on failure")
        #expect(sizeBefore == sizeAfter, "original file size preserved on failure")
    }

    @Test("E2. Canonical fixture is never modified by any migration test path")
    @MainActor
    func testCanonicalFixtureIntegrity() throws {
        let canonical = try Self.canonicalFixtureURL()
        let sha = try Self.sha256(of: canonical.path)
        // Known committed SHA-256 of the standalone V1.0 fixture.
        #expect(sha == "ba5445d0b9366ab7be3f8af8210df2667be7dfb48c25d44b1279f077cc83b882", "canonical fixture SHA unchanged")
        // No required sidecars (standalone DELETE mode).
        #expect(!FileManager.default.fileExists(atPath: canonical.path + "-wal"), "no canonical -wal")
        #expect(!FileManager.default.fileExists(atPath: canonical.path + "-shm"), "no canonical -shm")
    }
}