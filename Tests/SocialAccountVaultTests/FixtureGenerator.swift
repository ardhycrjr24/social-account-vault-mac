import Testing
import Foundation
import SwiftData
import SQLite3
@testable import SocialAccountVaultCore

/// Errors specific to fixture generation, WAL checkpointing, backup validation, and read-back audits.
enum FixtureGenerationError: Error, LocalizedError {
    case checkpointFailed(String)
    case backupFailed(String)
    case backupCorrupted(String)
    case sqliteConnectionFailed(String)
    case readBackFailed(String)

    var errorDescription: String? {
        switch self {
        case .checkpointFailed(let msg): return "WAL Checkpoint Failed: \(msg)"
        case .backupFailed(let msg): return "Backup Operation Failed: \(msg)"
        case .backupCorrupted(let msg): return "Backup PRAGMA integrity_check Failed: \(msg)"
        case .sqliteConnectionFailed(let msg): return "SQLite Connection Failed: \(msg)"
        case .readBackFailed(let msg): return "Post-Generation Read-Back Failed: \(msg)"
        }
    }
}

@Suite("V1 Fixture Generator Suite")
struct FixtureGeneratorSuite {

    // Deterministic Reference Timestamps (Zero dependence on Date.now)
    private static let baseEpoch: TimeInterval = 1793491200 // 2026-11-01T00:00:00Z
    private static let baseDate = Date(timeIntervalSince1970: baseEpoch)
    private static let domainExpDate = Date(timeIntervalSince1970: 1814399999) // 2027-06-30T23:59:59Z

    @Test("Verify Repository Root Discovery (Ancestor Match)")
    func verifyRepositoryRootDiscovery() throws {
        let rootURL = try Self.findProjectRoot()
        let fm = FileManager.default
        let hasPackageSwift = fm.fileExists(atPath: rootURL.appendingPathComponent("Package.swift").path)
        let hasTestsDir = fm.fileExists(atPath: rootURL.appendingPathComponent("Tests/SocialAccountVaultTests").path)
        #expect(hasPackageSwift, "Discovered root must contain Package.swift")
        #expect(hasTestsDir, "Discovered root must contain Tests/SocialAccountVaultTests")
        #expect(rootURL.lastPathComponent == "SocialAccountVault", "Discovered root directory name must be 'SocialAccountVault'")
    }

    @Test("Verify Online Backup API Produces Standalone Read-Only Database from WAL")
    func verifyOnlineBackupProducesStandaloneReadOnlyDatabase() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("vault_backup_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let fm = FileManager.default
        let srcPath = tempDir.appendingPathComponent("source_wal.sqlite").path
        let dstPath = tempDir.appendingPathComponent("backup_standalone.sqlite").path

        func logTestStage(_ stage: String) {
            let dbExists = fm.fileExists(atPath: dstPath)
            let shmExists = fm.fileExists(atPath: "\(dstPath)-shm")
            let walExists = fm.fileExists(atPath: "\(dstPath)-wal")
            print("[DIAGNOSTIC TEST - \(stage)] db: \(dbExists), shm: \(shmExists), wal: \(walExists)")
        }

        // 1. Create a WAL-mode SQLite database with tables and sample records
        try Self.withSQLiteConnection(at: srcPath, flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE) { db in
            try Self.withPreparedStatement(db: db, sql: "PRAGMA journal_mode = WAL;") { stmt in
                #expect(sqlite3_step(stmt) == SQLITE_ROW)
            }
            try Self.withPreparedStatement(db: db, sql: "CREATE TABLE item (id INTEGER PRIMARY KEY, title TEXT NOT NULL);") { stmt in
                #expect(sqlite3_step(stmt) == SQLITE_DONE)
            }
            try Self.withPreparedStatement(db: db, sql: "INSERT INTO item (id, title) VALUES (1, 'Test Record');") { stmt in
                #expect(sqlite3_step(stmt) == SQLITE_DONE)
            }
        }
        logTestStage("After source WAL database created")

        // 2. Perform SQLite Online Backup
        try Self.performOnlineBackup(from: srcPath, to: dstPath)
        logTestStage("After performOnlineBackup completed")

        // 3. Verify destination is a standalone file that passes integrity check via SQLITE_OPEN_READONLY
        try Self.verifyDatabaseIntegrity(at: dstPath)
        logTestStage("After verifyDatabaseIntegrity completed")

        // 4. Verify destination journal mode is DELETE (standalone single file, no -wal or -shm needed)
        try Self.withSQLiteConnection(at: dstPath, flags: SQLITE_OPEN_READONLY) { db in
            try Self.withPreparedStatement(db: db, sql: "PRAGMA journal_mode;") { stmt in
                #expect(sqlite3_step(stmt) == SQLITE_ROW)
                if let ptr = sqlite3_column_text(stmt, 0) {
                    let mode = String(cString: ptr)
                    print("[DIAGNOSTIC TEST] Read-only verification journal_mode query returned: '\(mode)'")
                    #expect(mode.lowercased() == "delete")
                }
            }
        }
        logTestStage("After read-only PRAGMA journal_mode connection closed")

        // 5. Verify no -shm or -wal companion files exist for the standalone backup
        #expect(!fm.fileExists(atPath: "\(dstPath)-wal"), "Standalone backup must not have -wal file")
        #expect(!fm.fileExists(atPath: "\(dstPath)-shm"), "Standalone backup must not have -shm file")
    }

    @Test("Verify VACUUM INTO Produces Standalone Read-Only Database from WAL")
    func verifyVacuumIntoProducesStandaloneReadOnlyDatabase() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("vault_vacuum_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let fm = FileManager.default
        let srcPath = tempDir.appendingPathComponent("source_wal.sqlite").path
        let dstPath = tempDir.appendingPathComponent("backup_vacuum.sqlite").path

        // 1. Create a WAL-mode SQLite database with tables and sample records
        try Self.withSQLiteConnection(at: srcPath, flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE) { db in
            try Self.withPreparedStatement(db: db, sql: "PRAGMA journal_mode = WAL;") { stmt in
                #expect(sqlite3_step(stmt) == SQLITE_ROW)
            }
            try Self.withPreparedStatement(db: db, sql: "CREATE TABLE item (id INTEGER PRIMARY KEY, title TEXT NOT NULL, score REAL);") { stmt in
                #expect(sqlite3_step(stmt) == SQLITE_DONE)
            }
            try Self.withPreparedStatement(db: db, sql: "INSERT INTO item (id, title, score) VALUES (1, 'Alpha Record', 99.5);") { stmt in
                #expect(sqlite3_step(stmt) == SQLITE_DONE)
            }
            try Self.withPreparedStatement(db: db, sql: "INSERT INTO item (id, title, score) VALUES (2, 'Beta Record', 88.0);") { stmt in
                #expect(sqlite3_step(stmt) == SQLITE_DONE)
            }
        }

        // 2. Perform VACUUM INTO backup
        try Self.performVacuumBackup(from: srcPath, to: dstPath)

        // 3. Verify header bytes 18 and 19 are 0x01 0x01 (format version 1 = rollback journal mode)
        let versions = Self.readDatabaseHeaderFormatVersion(at: dstPath)
        #expect(versions?.writeVersion == 1, "Header byte 18 must be 0x01 (write format version 1)")
        #expect(versions?.readVersion == 1, "Header byte 19 must be 0x01 (read format version 1)")

        // 4. Verify no companion sidecar files (-wal or -shm) exist
        #expect(!fm.fileExists(atPath: "\(dstPath)-wal"), "Vacuum backup must not have -wal file")
        #expect(!fm.fileExists(atPath: "\(dstPath)-shm"), "Vacuum backup must not have -shm file")

        // 5. Verify database integrity check and foreign key check pass on standalone read-only database
        try Self.verifyDatabaseIntegrity(at: dstPath)

        // 6. Verify journal mode is DELETE via SQLITE_OPEN_READONLY
        try Self.withSQLiteConnection(at: dstPath, flags: SQLITE_OPEN_READONLY) { db in
            try Self.withPreparedStatement(db: db, sql: "PRAGMA journal_mode;") { stmt in
                #expect(sqlite3_step(stmt) == SQLITE_ROW)
                if let ptr = sqlite3_column_text(stmt, 0) {
                    let mode = String(cString: ptr)
                    #expect(mode.lowercased() == "delete")
                }
            }

            // 7. Compare content: verify data records match exactly
            try Self.withPreparedStatement(db: db, sql: "SELECT id, title, score FROM item ORDER BY id;") { stmt in
                #expect(sqlite3_step(stmt) == SQLITE_ROW)
                #expect(sqlite3_column_int64(stmt, 0) == 1)
                #expect(String(cString: sqlite3_column_text(stmt, 1)!) == "Alpha Record")
                #expect(sqlite3_column_double(stmt, 2) == 99.5)

                #expect(sqlite3_step(stmt) == SQLITE_ROW)
                #expect(sqlite3_column_int64(stmt, 0) == 2)
                #expect(String(cString: sqlite3_column_text(stmt, 1)!) == "Beta Record")
                #expect(sqlite3_column_double(stmt, 2) == 88.0)

                #expect(sqlite3_step(stmt) == SQLITE_DONE)
            }
        }
    }

    @Test("Verify VACUUM INTO Rejects Existing Destination File to Prevent Accidental Overwrite")
    func verifyVacuumBackupRejectsExistingDestination() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("vault_dest_safety_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let srcPath = tempDir.appendingPathComponent("source_wal.sqlite").path
        let dstPath = tempDir.appendingPathComponent("preexisting_sentinel_backup.sqlite").path

        // 1. Create source WAL database
        try Self.withSQLiteConnection(at: srcPath, flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE) { db in
            try Self.withPreparedStatement(db: db, sql: "PRAGMA journal_mode = WAL;") { stmt in
                #expect(sqlite3_step(stmt) == SQLITE_ROW)
            }
            try Self.withPreparedStatement(db: db, sql: "CREATE TABLE t (id INT PRIMARY KEY, note TEXT);") { stmt in
                #expect(sqlite3_step(stmt) == SQLITE_DONE)
            }
            try Self.withPreparedStatement(db: db, sql: "INSERT INTO t (id, note) VALUES (1, 'Source payload data');") { stmt in
                #expect(sqlite3_step(stmt) == SQLITE_DONE)
            }
        }
        let srcDataBefore = try Data(contentsOf: URL(fileURLWithPath: srcPath))

        // 2. Create destination already containing sentinel data
        let sentinelContent = "SENTINEL_PROTECTED_DATA_\(UUID().uuidString)"
        let sentinelDataBefore = Data(sentinelContent.utf8)
        try sentinelDataBefore.write(to: URL(fileURLWithPath: dstPath))

        // 3. Helper dipanggil dengan destination yang sama -> operasi ditolak
        #expect(throws: Error.self) {
            try Self.performVacuumBackup(from: srcPath, to: dstPath, sourceFlags: SQLITE_OPEN_READWRITE)
        }

        // 4. File sentinel tetap identik
        let sentinelDataAfter = try Data(contentsOf: URL(fileURLWithPath: dstPath))
        #expect(sentinelDataAfter == sentinelDataBefore, "Sentinel file content must remain 100% untouched")
        #expect(String(data: sentinelDataAfter, encoding: .utf8) == sentinelContent)

        // 5. Tidak ada perubahan pada file sumber
        let srcDataAfter = try Data(contentsOf: URL(fileURLWithPath: srcPath))
        #expect(srcDataAfter == srcDataBefore, "Source file content must remain 100% untouched")
    }

    @Test("Verify VACUUM INTO Preserves SwiftData Schema, Metadata, UUIDs, and Relationships")
    @MainActor
    func verifyVacuumBackupPreservesSwiftDataCompatibility() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("vault_vacuum_swiftdata_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let fm = FileManager.default
        let projectRoot = try Self.findProjectRoot()
        let fixturePath = projectRoot.appendingPathComponent("Tests/Fixtures/v1_migration_fixture.sqlite").path

        let dstPath = tempDir.appendingPathComponent("backup_swiftdata_standalone.sqlite").path

        // Task 1: Rancang test terisolasi yang menyalin fixture asli ke temporary directory
        let srcPath: String
        if fm.fileExists(atPath: fixturePath) {
            let isolatedCopyPath = tempDir.appendingPathComponent("fixture_isolated_copy.sqlite").path
            try fm.copyItem(atPath: fixturePath, toPath: isolatedCopyPath)
            srcPath = isolatedCopyPath
            print("[ISOLATION] Fixture copied to temporary path: '\(srcPath)'")
        } else {
            let dynURL = tempDir.appendingPathComponent("dynamic_swiftdata.sqlite")
            let container = try DatabaseConfiguration.createModelContainer(at: dynURL, inMemory: false)
            let context = ModelContext(container)
            let cat = PlatformCategory(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!,
                name: "YouTube",
                iconName: "play.rectangle.fill",
                displayOrder: 1,
                isDefault: true,
                createdAt: Self.baseDate,
                updatedAt: Self.baseDate
            )
            context.insert(cat)
            let acc = Account(
                id: UUID(uuidString: "00000000-0000-0000-0001-000000000001")!,
                name: "Aruna Studio Official",
                platform: PlatformType.youtube.rawValue,
                username: "arunastudio",
                emailReference: "contact@arunastudio.example.com",
                profileURLString: "https://youtube.com/@arunastudio",
                officialDashboardURLString: "https://studio.youtube.com",
                accountType: .creator,
                accountStatus: .active,
                monetizationStatus: .monetized,
                notes: "Primary production studio channel.",
                isArchived: false,
                creationDate: Self.baseDate.addingTimeInterval(-86400 * 365),
                lastCheckedDate: Self.baseDate,
                domainExpirationDate: nil,
                createdAt: Self.baseDate,
                updatedAt: Self.baseDate,
                category: cat
            )
            context.insert(acc)
            try context.save()
            srcPath = dynURL.path
        }

        // Tahap 1 — Audit path dan filesystem
        print("[DIAGNOSTIC TAHAP 1 - Path & Filesystem]")
        print("  1. srcPath (absolute): '\(srcPath)'")
        let srcExists = fm.fileExists(atPath: srcPath)
        print("  2. srcPath exists: \(srcExists)")
        if let attrs = try? fm.attributesOfItem(atPath: srcPath) {
            let size = attrs[.size] as? Int64 ?? -1
            print("  3. srcPath size: \(size) bytes")
        } else {
            print("  3. srcPath size: unable to get attributes")
        }
        let srcDir = (srcPath as NSString).deletingLastPathComponent
        print("  4. srcDir: '\(srcDir)' (readable: \(fm.isReadableFile(atPath: srcDir)), writable: \(fm.isWritableFile(atPath: srcDir)))")
        print("  5. dstPath (absolute): '\(dstPath)'")
        let dstDir = tempDir.path
        print("  6. dstDir: '\(dstDir)' (exists: \(fm.fileExists(atPath: dstDir)), writable: \(fm.isWritableFile(atPath: dstDir)))")
        print("  7. dstFile already exists before backup: \(fm.fileExists(atPath: dstPath))")
        print("  8. src companion -wal exists: \(fm.fileExists(atPath: "\(srcPath)-wal"))")
        print("  9. src companion -shm exists: \(fm.fileExists(atPath: "\(srcPath)-shm"))")

        // 10. Check if src can be opened by another read handle
        if let testHandle = FileHandle(forReadingAtPath: srcPath) {
            print("  10. src file can be opened for reading: YES (unlocked by other processes)")
            try? testHandle.close()
        } else {
            print("  10. src file can be opened for reading: NO (locked or inaccessible)")
        }

        // Tasks 2 & 3: Buka salinan dengan SQLITE_OPEN_READWRITE, validasi query sederhana, integrity_check, foreign_key_check
        var sourceAccountCount: Int64 = -1
        try Self.withSQLiteConnection(at: srcPath, flags: SQLITE_OPEN_READWRITE) { db in
            try Self.withPreparedStatement(db: db, sql: "SELECT COUNT(*) FROM ZACCOUNT;") { stmt in
                if sqlite3_step(stmt) == SQLITE_ROW {
                    sourceAccountCount = sqlite3_column_int64(stmt, 0)
                }
            }
            try Self.withPreparedStatement(db: db, sql: "PRAGMA integrity_check;") { stmt in
                #expect(sqlite3_step(stmt) == SQLITE_ROW)
                if let ptr = sqlite3_column_text(stmt, 0) {
                    #expect(String(cString: ptr).lowercased() == "ok")
                }
            }
            try Self.withPreparedStatement(db: db, sql: "PRAGMA foreign_key_check;") { stmt in
                #expect(sqlite3_step(stmt) == SQLITE_DONE, "Source copy must pass foreign key check with zero violations")
            }
        }
        print("[ISOLATION] Source copy validated in READWRITE mode with account count: \(sourceAccountCount)")
        #expect(sourceAccountCount > 0, "Source database must contain accounts")

        // Task 4: Jalankan VACUUM INTO dari salinan tersebut ke file backup standalone yang baru (buka sumber READWRITE)
        try Self.performVacuumBackup(from: srcPath, to: dstPath, sourceFlags: SQLITE_OPEN_READWRITE)

        // Task 5: Pastikan backup tidak memiliki ketergantungan pada WAL/SHM (format version 1 = rollback journal, no sidecars)
        let versions = Self.readDatabaseHeaderFormatVersion(at: dstPath)
        #expect(versions?.writeVersion == 1, "Backup must have write version 1 (rollback journal)")
        #expect(versions?.readVersion == 1, "Backup must have read version 1 (rollback journal)")
        #expect(!fm.fileExists(atPath: "\(dstPath)-wal"), "Backup must not have -wal sidecar")
        #expect(!fm.fileExists(atPath: "\(dstPath)-shm"), "Backup must not have -shm sidecar")

        // Task 6: Buka backup dengan SQLITE_OPEN_READONLY dan lakukan integrity_check serta foreign_key_check
        try Self.verifyDatabaseIntegrity(at: dstPath)

        // 5. Compare schema elements (tables, indexes, triggers) between source and backup
        var srcSchemaElements: [String: String] = [:]
        try Self.withSQLiteConnection(at: srcPath, flags: SQLITE_OPEN_READONLY) { db in
            try Self.withPreparedStatement(db: db, sql: "SELECT type || ':' || name, sql FROM sqlite_master WHERE type IN ('table', 'index', 'trigger') AND sql IS NOT NULL;") { stmt in
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let keyPtr = sqlite3_column_text(stmt, 0), let sqlPtr = sqlite3_column_text(stmt, 1) {
                        srcSchemaElements[String(cString: keyPtr)] = String(cString: sqlPtr)
                    }
                }
            }
        }

        var dstSchemaElements: [String: String] = [:]
        try Self.withSQLiteConnection(at: dstPath, flags: SQLITE_OPEN_READONLY) { db in
            try Self.withPreparedStatement(db: db, sql: "SELECT type || ':' || name, sql FROM sqlite_master WHERE type IN ('table', 'index', 'trigger') AND sql IS NOT NULL;") { stmt in
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let keyPtr = sqlite3_column_text(stmt, 0), let sqlPtr = sqlite3_column_text(stmt, 1) {
                        dstSchemaElements[String(cString: keyPtr)] = String(cString: sqlPtr)
                    }
                }
            }
        }

        #expect(!srcSchemaElements.isEmpty, "Source schema must contain tables and indexes")
        #expect(srcSchemaElements == dstSchemaElements, "Backup schema (tables, indexes, triggers) must be identical to source")

        // 6. Deep entity and data comparison across SwiftData entities (Account, PlatformCategory, AccountDetail, ActivityLog)
        struct CategoryRow: Equatable {
            let pk: Int64
            let name: String
            let iconName: String
            let displayOrder: Int32
            let isDefault: Int32
            let createdAt: Double
            let updatedAt: Double
            let uuidHex: String
        }

        func loadCategories(db: OpaquePointer) throws -> [Int64: CategoryRow] {
            var rows: [Int64: CategoryRow] = [:]
            let sql = "SELECT Z_PK, ZNAME, ZICONNAME, ZDISPLAYORDER, ZISDEFAULT, ZCREATEDAT, ZUPDATEDAT, hex(ZID) FROM ZPLATFORMCATEGORY;"
            try Self.withPreparedStatement(db: db, sql: sql) { stmt in
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let pk = sqlite3_column_int64(stmt, 0)
                    let name = String(cString: sqlite3_column_text(stmt, 1)!)
                    let icon = String(cString: sqlite3_column_text(stmt, 2)!)
                    let order = sqlite3_column_int(stmt, 3)
                    let isDef = sqlite3_column_int(stmt, 4)
                    let created = sqlite3_column_double(stmt, 5)
                    let updated = sqlite3_column_double(stmt, 6)
                    let uuid = String(cString: sqlite3_column_text(stmt, 7)!)
                    rows[pk] = CategoryRow(
                        pk: pk, name: name, iconName: icon, displayOrder: order,
                        isDefault: isDef, createdAt: created, updatedAt: updated, uuidHex: uuid
                    )
                }
            }
            return rows
        }

        struct AccountRow: Equatable {
            let pk: Int64
            let name: String
            let platform: String
            let username: String
            let emailReference: String
            let profileURLString: String
            let officialDashboardURLString: String
            let accountTypeRaw: String
            let accountStatusRaw: String
            let monetizationStatusRaw: String
            let notes: String
            let isArchived: Int32
            let creationDate: Double
            let lastCheckedDate: Double
            let domainExpirationDate: Double?
            let createdAt: Double
            let updatedAt: Double
            let categoryPK: Int64?
            let uuidHex: String
        }

        func loadAccounts(db: OpaquePointer) throws -> [Int64: AccountRow] {
            var rows: [Int64: AccountRow] = [:]
            let sql = """
            SELECT Z_PK, ZNAME, ZPLATFORM, ZUSERNAME, ZEMAILREFERENCE,
                   COALESCE(ZPROFILEURLSTRING, ''), COALESCE(ZOFFICIALDASHBOARDURLSTRING, ''),
                   ZACCOUNTTYPERAW, ZACCOUNTSTATUSRAW, ZMONETIZATIONSTATUSRAW,
                   COALESCE(ZNOTES, ''), ZISARCHIVED, ZCREATIONDATE, ZLASTCHECKEDDATE,
                   COALESCE(ZDOMAINEXPIRATIONDATE, -1.0), ZCREATEDAT, ZUPDATEDAT,
                   COALESCE(ZCATEGORY, -1), hex(ZID)
            FROM ZACCOUNT;
            """
            try Self.withPreparedStatement(db: db, sql: sql) { stmt in
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let pk = sqlite3_column_int64(stmt, 0)
                    let name = String(cString: sqlite3_column_text(stmt, 1)!)
                    let plat = String(cString: sqlite3_column_text(stmt, 2)!)
                    let user = String(cString: sqlite3_column_text(stmt, 3)!)
                    let email = String(cString: sqlite3_column_text(stmt, 4)!)
                    let profile = String(cString: sqlite3_column_text(stmt, 5)!)
                    let dash = String(cString: sqlite3_column_text(stmt, 6)!)
                    let type = String(cString: sqlite3_column_text(stmt, 7)!)
                    let status = String(cString: sqlite3_column_text(stmt, 8)!)
                    let monet = String(cString: sqlite3_column_text(stmt, 9)!)
                    let notes = String(cString: sqlite3_column_text(stmt, 10)!)
                    let arch = sqlite3_column_int(stmt, 11)
                    let cDate = sqlite3_column_double(stmt, 12)
                    let lDate = sqlite3_column_double(stmt, 13)
                    let rawDomainExp = sqlite3_column_double(stmt, 14)
                    let domainExp = rawDomainExp >= 0 ? rawDomainExp : nil
                    let created = sqlite3_column_double(stmt, 15)
                    let updated = sqlite3_column_double(stmt, 16)
                    let rawCat = sqlite3_column_int64(stmt, 17)
                    let catPK = rawCat >= 0 ? rawCat : nil
                    let uuid = String(cString: sqlite3_column_text(stmt, 18)!)

                    rows[pk] = AccountRow(
                        pk: pk, name: name, platform: plat, username: user,
                        emailReference: email, profileURLString: profile,
                        officialDashboardURLString: dash, accountTypeRaw: type,
                        accountStatusRaw: status, monetizationStatusRaw: monet,
                        notes: notes, isArchived: arch, creationDate: cDate,
                        lastCheckedDate: lDate, domainExpirationDate: domainExp,
                        createdAt: created, updatedAt: updated, categoryPK: catPK,
                        uuidHex: uuid
                    )
                }
            }
            return rows
        }

        struct DetailRow: Equatable {
            let pk: Int64
            let accountPK: Int64
            let key: String
            let value: String
            let createdAt: Double
            let updatedAt: Double
            let uuidHex: String
        }

        func loadDetails(db: OpaquePointer) throws -> [Int64: DetailRow] {
            var rows: [Int64: DetailRow] = [:]
            let sql = "SELECT Z_PK, ZACCOUNT, ZKEY, ZVALUE, ZCREATEDAT, ZUPDATEDAT, hex(ZID) FROM ZACCOUNTDETAIL;"
            try Self.withPreparedStatement(db: db, sql: sql) { stmt in
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let pk = sqlite3_column_int64(stmt, 0)
                    let accPK = sqlite3_column_int64(stmt, 1)
                    let key = String(cString: sqlite3_column_text(stmt, 2)!)
                    let val = String(cString: sqlite3_column_text(stmt, 3)!)
                    let created = sqlite3_column_double(stmt, 4)
                    let updated = sqlite3_column_double(stmt, 5)
                    let uuid = String(cString: sqlite3_column_text(stmt, 6)!)
                    rows[pk] = DetailRow(
                        pk: pk, accountPK: accPK, key: key, value: val,
                        createdAt: created, updatedAt: updated, uuidHex: uuid
                    )
                }
            }
            return rows
        }

        struct LogRow: Equatable {
            let pk: Int64
            let accountPK: Int64
            let actionType: String
            let details: String
            let timestamp: Double
            let sequenceNumber: Int64
            let createdAt: Double
            let updatedAt: Double
            let uuidHex: String
        }

        func loadLogs(db: OpaquePointer) throws -> [Int64: LogRow] {
            var rows: [Int64: LogRow] = [:]
            let sql = "SELECT Z_PK, ZACCOUNT, ZACTIONTYPE, ZDETAILS, ZTIMESTAMP, ZSEQUENCENUMBER, ZCREATEDAT, ZUPDATEDAT, hex(ZID) FROM ZACTIVITYLOG;"
            try Self.withPreparedStatement(db: db, sql: sql) { stmt in
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let pk = sqlite3_column_int64(stmt, 0)
                    let accPK = sqlite3_column_int64(stmt, 1)
                    let action = String(cString: sqlite3_column_text(stmt, 2)!)
                    let det = String(cString: sqlite3_column_text(stmt, 3)!)
                    let ts = sqlite3_column_double(stmt, 4)
                    let seq = sqlite3_column_int64(stmt, 5)
                    let created = sqlite3_column_double(stmt, 6)
                    let updated = sqlite3_column_double(stmt, 7)
                    let uuid = String(cString: sqlite3_column_text(stmt, 8)!)
                    rows[pk] = LogRow(
                        pk: pk, accountPK: accPK, actionType: action, details: det,
                        timestamp: ts, sequenceNumber: seq, createdAt: created,
                        updatedAt: updated, uuidHex: uuid
                    )
                }
            }
            return rows
        }

        try Self.withSQLiteConnection(at: srcPath, flags: SQLITE_OPEN_READONLY) { srcDb in
            try Self.withSQLiteConnection(at: dstPath, flags: SQLITE_OPEN_READONLY) { dstDb in
                // 1. Verify PlatformCategory records match completely
                let srcCats = try loadCategories(db: srcDb)
                let dstCats = try loadCategories(db: dstDb)
                #expect(srcCats.count == dstCats.count, "PlatformCategory record count must match")
                for (pk, srcCat) in srcCats {
                    let dstCat = dstCats[pk]
                    #expect(dstCat == srcCat, "PlatformCategory mismatch at PK \(pk) (UUID: \(srcCat.uuidHex))")
                }

                // 2. Verify Account records match completely (all fields, nullable, multiline, timestamps, relations, UUID)
                let srcAccs = try loadAccounts(db: srcDb)
                let dstAccs = try loadAccounts(db: dstDb)
                #expect(srcAccs.count == dstAccs.count, "Account record count must match")
                for (pk, srcAcc) in srcAccs {
                    let dstAcc = dstAccs[pk]
                    #expect(dstAcc == srcAcc, "Account mismatch at PK \(pk) (UUID: \(srcAcc.uuidHex))")
                }

                // 3. Verify AccountDetail records match completely
                let srcDets = try loadDetails(db: srcDb)
                let dstDets = try loadDetails(db: dstDb)
                #expect(srcDets.count == dstDets.count, "AccountDetail record count must match")
                for (pk, srcDet) in srcDets {
                    let dstDet = dstDets[pk]
                    #expect(dstDet == srcDet, "AccountDetail mismatch at PK \(pk) (UUID: \(srcDet.uuidHex))")
                }

                // 4. Verify ActivityLog records match completely
                let srcLogs = try loadLogs(db: srcDb)
                let dstLogs = try loadLogs(db: dstDb)
                #expect(srcLogs.count == dstLogs.count, "ActivityLog record count must match")
                for (pk, srcLog) in srcLogs {
                    let dstLog = dstLogs[pk]
                    #expect(dstLog == srcLog, "ActivityLog mismatch at PK \(pk) (UUID: \(srcLog.uuidHex))")
                }
            }
        }

        // 7. Verify opening dstPath read-only leaves zero sidecars
        try Self.withSQLiteConnection(at: dstPath, flags: SQLITE_OPEN_READONLY) { db in
            try Self.withPreparedStatement(db: db, sql: "PRAGMA journal_mode;") { stmt in
                #expect(sqlite3_step(stmt) == SQLITE_ROW)
                if let ptr = sqlite3_column_text(stmt, 0) {
                    let mode = String(cString: ptr)
                    #expect(mode.lowercased() == "delete")
                }
            }
        }
        #expect(!fm.fileExists(atPath: "\(dstPath)-wal"), "Read-only access must not produce -wal file")
        #expect(!fm.fileExists(atPath: "\(dstPath)-shm"), "Read-only access must not produce -shm file")
    }

    @Test("Verify Standalone Backup Loads in SwiftData ModelContainer (Task 8 & 9)")
    @MainActor
    func verifyStandaloneBackupLoadsInSwiftDataModelContainer() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("vault_modelcontainer_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let fm = FileManager.default
        let projectRoot = try Self.findProjectRoot()
        let fixturePath = projectRoot.appendingPathComponent("Tests/Fixtures/v1_migration_fixture.sqlite").path

        guard fm.fileExists(atPath: fixturePath) else {
            print("[SWIFTDATA TEST] Fixture file not found at \(fixturePath)")
            return
        }

        // 1. Copy fixture to isolated temp directory and create standalone backup via VACUUM INTO
        let tempSourcePath = tempDir.appendingPathComponent("fixture_for_mc.sqlite").path
        try fm.copyItem(atPath: fixturePath, toPath: tempSourcePath)

        let standaloneBackupURL = tempDir.appendingPathComponent("backup_for_mc.sqlite")
        try Self.performVacuumBackup(from: tempSourcePath, to: standaloneBackupURL.path, sourceFlags: SQLITE_OPEN_READWRITE)

        // 2. Verify standalone properties
        #expect(!fm.fileExists(atPath: "\(standaloneBackupURL.path)-wal"), "Backup must not have -wal file")
        #expect(!fm.fileExists(atPath: "\(standaloneBackupURL.path)-shm"), "Backup must not have -shm file")

        // 3. Task 8: Load standalone backup via SwiftData ModelContainer
        let schema = DatabaseConfiguration.schema
        let config = ModelConfiguration("StandaloneVaultStore", schema: schema, url: standaloneBackupURL, allowsSave: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let accounts = try context.fetch(FetchDescriptor<Account>())
        print("[SWIFTDATA TEST] Successfully fetched \(accounts.count) accounts from standalone backup")
        #expect(accounts.count == 5, "ModelContainer must load 5 accounts from standalone backup")

        let categories = try context.fetch(FetchDescriptor<PlatformCategory>())
        print("[SWIFTDATA TEST] Successfully fetched \(categories.count) categories from standalone backup")
        #expect(categories.count == 9, "ModelContainer must load 9 categories from standalone backup")
        #expect(categories.contains { $0.name == "Creator Tools" }, "ModelContainer must contain custom category 'Creator Tools'")

        let details = try context.fetch(FetchDescriptor<AccountDetail>())
        print("[SWIFTDATA TEST] Successfully fetched \(details.count) details from standalone backup")
        #expect(details.count == 7, "ModelContainer must load 7 account details from standalone backup")

        let logs = try context.fetch(FetchDescriptor<ActivityLog>())
        print("[SWIFTDATA TEST] Successfully fetched \(logs.count) activity logs from standalone backup")
        #expect(logs.count == 14, "ModelContainer must load 14 activity logs from standalone backup")
    }

    @Test("Diagnostic: Isolated Experiment on Fixture Vacuum Compatibility (Tahap 4)")
    func diagnoseFixtureVacuumCompatibility() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("vault_diag_exp_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let fm = FileManager.default
        let projectRoot = try Self.findProjectRoot()
        let fixturePath = projectRoot.appendingPathComponent("Tests/Fixtures/v1_migration_fixture.sqlite").path

        print("[DIAGNOSTIC TAHAP 4 - Isolated Experiment]")
        print("  Fixture path: '\(fixturePath)' (exists: \(fm.fileExists(atPath: fixturePath)))")

        guard fm.fileExists(atPath: fixturePath) else {
            print("  [SKIP] Fixture file not found at \(fixturePath)")
            return
        }

        // 1. Direct READONLY open on original fixture without companion files (demonstrating SQLITE_CANTOPEN)
        do {
            try Self.withSQLiteConnection(at: fixturePath, flags: SQLITE_OPEN_READONLY) { db in
                try Self.withPreparedStatement(db: db, sql: "SELECT COUNT(*) FROM ZACCOUNT;") { stmt in
                    _ = sqlite3_step(stmt)
                }
            }
            print("  1. Direct READONLY open on original fixture: SUCCEEDED")
        } catch {
            print("  1. Direct READONLY open on original fixture: FAILED as expected with SQLITE_CANTOPEN: \(error.localizedDescription)")
        }

        // 2. Copy fixture to temp directory and open with SQLITE_OPEN_READWRITE
        let tempCopyPath = tempDir.appendingPathComponent("fixture_temp_rw.sqlite").path
        try fm.copyItem(atPath: fixturePath, toPath: tempCopyPath)
        var rwAccountCount: Int64 = -1
        try Self.withSQLiteConnection(at: tempCopyPath, flags: SQLITE_OPEN_READWRITE) { db in
            try Self.withPreparedStatement(db: db, sql: "SELECT COUNT(*) FROM ZACCOUNT;") { stmt in
                if sqlite3_step(stmt) == SQLITE_ROW {
                    rwAccountCount = sqlite3_column_int64(stmt, 0)
                }
            }
        }
        print("  2. READWRITE open on temp copy: SUCCEEDED with account count: \(rwAccountCount)")
        #expect(rwAccountCount == 5, "Temp copy must return 5 accounts in READWRITE mode")

        // 3. VACUUM INTO from temp copy to standalone backup
        let standaloneDst = tempDir.appendingPathComponent("vacuum_standalone.sqlite").path
        do {
            try Self.performVacuumBackup(from: tempCopyPath, to: standaloneDst, sourceFlags: SQLITE_OPEN_READWRITE)
            print("  3. performVacuumBackup from temp copy to standaloneDst: SUCCESS")
            #expect(fm.fileExists(atPath: standaloneDst), "Standalone backup must exist")
        } catch {
            print("  3. performVacuumBackup from temp copy to standaloneDst FAILED: \(error)")
        }

        // 4. Verify standalone backup in SQLITE_OPEN_READONLY with zero sidecars
        try Self.verifyDatabaseIntegrity(at: standaloneDst)
        #expect(!fm.fileExists(atPath: "\(standaloneDst)-wal"), "Standalone backup must have no -wal file")
        #expect(!fm.fileExists(atPath: "\(standaloneDst)-shm"), "Standalone backup must have no -shm file")
        print("  4. Standalone backup verified READONLY with zero sidecars: SUCCESS")

        // 5. Compare with synthetic WAL database
        let synthSrc = tempDir.appendingPathComponent("synth_src.sqlite").path
        let synthDst = tempDir.appendingPathComponent("synth_dst.sqlite").path
        try Self.withSQLiteConnection(at: synthSrc, flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE) { db in
            try Self.withPreparedStatement(db: db, sql: "PRAGMA journal_mode = WAL;") { stmt in
                _ = sqlite3_step(stmt)
            }
            try Self.withPreparedStatement(db: db, sql: "CREATE TABLE synth_item (id INT PRIMARY KEY, val TEXT);") { stmt in
                _ = sqlite3_step(stmt)
            }
            try Self.withPreparedStatement(db: db, sql: "INSERT INTO synth_item VALUES (1, 'demo');") { stmt in
                _ = sqlite3_step(stmt)
            }
        }
        do {
            try Self.performVacuumBackup(from: synthSrc, to: synthDst)
            print("  5. performVacuumBackup on synthetic DB: SUCCESS")
            #expect(fm.fileExists(atPath: synthDst), "Synthetic backup file must exist")
        } catch {
            print("  5. performVacuumBackup on synthetic DB FAILED: \(error)")
        }
    }

    @Test("Verify Database Integrity Check Detects Corruption")
    func verifyDatabaseIntegrityDetectsCorruption() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("vault_corrupt_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let corruptPath = tempDir.appendingPathComponent("corrupted.sqlite").path
        let garbage = Data("SQLite format 3\0\u{FF}\u{FE}InvalidCorruptedPageDataPayload".utf8)
        try garbage.write(to: URL(fileURLWithPath: corruptPath))

        #expect(throws: Error.self) {
            try Self.verifyDatabaseIntegrity(at: corruptPath)
        }
    }

    @Test("Verify Database Integrity Check Detects Foreign Key Violation")
    func verifyDatabaseIntegrityDetectsForeignKeyViolation() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("vault_fk_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let fkPath = tempDir.appendingPathComponent("fk_violation.sqlite").path

        try Self.withSQLiteConnection(at: fkPath, flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE) { db in
            try Self.withPreparedStatement(db: db, sql: "CREATE TABLE parent (id INTEGER PRIMARY KEY);") { stmt in
                #expect(sqlite3_step(stmt) == SQLITE_DONE)
            }
            try Self.withPreparedStatement(db: db, sql: "CREATE TABLE child (id INTEGER PRIMARY KEY, p_id INTEGER REFERENCES parent(id));") { stmt in
                #expect(sqlite3_step(stmt) == SQLITE_DONE)
            }
            try Self.withPreparedStatement(db: db, sql: "PRAGMA foreign_keys = OFF;") { stmt in
                #expect(sqlite3_step(stmt) == SQLITE_DONE)
            }
            try Self.withPreparedStatement(db: db, sql: "INSERT INTO child (id, p_id) VALUES (1, 9999);") { stmt in
                #expect(sqlite3_step(stmt) == SQLITE_DONE)
            }
        }

        #expect(throws: Error.self) {
            try Self.verifyDatabaseIntegrity(at: fkPath)
        }
    }

    @Test("Verify Online Backup Handles Invalid Source Path Gracefully")
    func verifyOnlineBackupHandlesInvalidSourcePath() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("vault_invalid_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let invalidSrc = tempDir.appendingPathComponent("nonexistent_source.sqlite").path
        let dstPath = tempDir.appendingPathComponent("backup.sqlite").path

        #expect(throws: Error.self) {
            try Self.performOnlineBackup(from: invalidSrc, to: dstPath)
        }
    }

    @Test(
        "Generate Authentic V1.0 Migration Fixture (Opt-In)",
        .enabled(if: ProcessInfo.processInfo.environment["GENERATE_V1_FIXTURE"] == "1")
    )
    @MainActor
    func generateFixture() throws {
        // 1. Double Isolation Guard
        guard ProcessInfo.processInfo.environment["GENERATE_V1_FIXTURE"] == "1" else {
            print("[FIXTURE GENERATOR] Opt-in flag not detected. Generation skipped.")
            return
        }

        let projectRoot = try Self.findProjectRoot()
        let fixturesDir = projectRoot.appendingPathComponent("Tests/Fixtures", isDirectory: true)
        try FileManager.default.createDirectory(at: fixturesDir, withIntermediateDirectories: true)

        let fixtureURL = fixturesDir.appendingPathComponent("v1_migration_fixture.sqlite")
        let basePath = fixtureURL.path
        let fileManager = FileManager.default

        // 2. Strict Backup Safety Protocol (Isolated temporary copy + VACUUM INTO + Standalone verification)
        if fileManager.fileExists(atPath: basePath) {
            let allowOverwrite = ProcessInfo.processInfo.environment["OVERWRITE_FIXTURE"] == "1"
            guard allowOverwrite else {
                print("[FIXTURE GENERATOR] HALTED: Existing fixture detected at \(basePath).")
                print("[FIXTURE GENERATOR] Set OVERWRITE_FIXTURE=1 to authorize replacement.")
                return
            }

            // Step 2A: Prepare unique destination path in Backups/
            let backupsDir = fixturesDir.appendingPathComponent("Backups", isDirectory: true)
            try fileManager.createDirectory(at: backupsDir, withIntermediateDirectories: true)

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
            let dateString = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let backupFileName = "v1_migration_fixture_\(dateString)_\(UUID().uuidString.prefix(8)).sqlite"
            let backupURL = backupsDir.appendingPathComponent(backupFileName)
            let backupPath = backupURL.path

            // Step 2B: Isolated temporary directory for backup creation
            // Original fixture is NEVER opened with SQLITE_OPEN_READWRITE directly.
            let tempDir = fileManager.temporaryDirectory.appendingPathComponent("vault_backup_isolation_\(UUID().uuidString)")
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer {
                try? fileManager.removeItem(at: tempDir)
            }

            let tempCopyPath = tempDir.appendingPathComponent("fixture_source_copy.sqlite").path
            try fileManager.copyItem(atPath: basePath, toPath: tempCopyPath)
            if fileManager.fileExists(atPath: "\(basePath)-wal") {
                try fileManager.copyItem(atPath: "\(basePath)-wal", toPath: "\(tempCopyPath)-wal")
            }
            if fileManager.fileExists(atPath: "\(basePath)-shm") {
                try fileManager.copyItem(atPath: "\(basePath)-shm", toPath: "\(tempCopyPath)-shm")
            }

            // Step 2C: VACUUM INTO from temporary copy opened with SQLITE_OPEN_READWRITE
            try Self.performVacuumBackup(from: tempCopyPath, to: backupPath, sourceFlags: SQLITE_OPEN_READWRITE)

            // Step 2D: Thoroughly verify standalone backup while original fixture remains untouched
            // 1. Verify standalone header format version 1 (rollback journal 0x01 0x01)
            guard let versions = Self.readDatabaseHeaderFormatVersion(at: backupPath),
                  versions.writeVersion == 1, versions.readVersion == 1 else {
                throw FixtureGenerationError.backupCorrupted("Backup header format version verification failed for \(backupPath)")
            }

            // 2. Verify no sidecar files accompany the standalone backup
            guard !fileManager.fileExists(atPath: "\(backupPath)-wal"),
                  !fileManager.fileExists(atPath: "\(backupPath)-shm") else {
                throw FixtureGenerationError.backupCorrupted("Standalone backup must not produce companion -wal or -shm files")
            }

            // 3. Verify READONLY integrity_check = ok and foreign_key_check clean
            try Self.verifyDatabaseIntegrity(at: backupPath)
            print("[FIXTURE GENERATOR] Standalone backup 100% verified healthy: \(backupPath)")

            // Step 2E: Remove old files only after backup is 100% verified healthy
            try fileManager.removeItem(atPath: basePath)
            if fileManager.fileExists(atPath: "\(basePath)-wal") {
                try fileManager.removeItem(atPath: "\(basePath)-wal")
            }
            if fileManager.fileExists(atPath: "\(basePath)-shm") {
                try fileManager.removeItem(atPath: "\(basePath)-shm")
            }
        }

        // 3. Isolated SwiftData Scope (Guarantees container deallocation before WAL flush)
        try { () throws in
            let container = try DatabaseConfiguration.createModelContainer(at: fixtureURL, inMemory: false)
            let context = ModelContext(container)

            // 4. Platform Categories (Born deterministic with fixed UUIDs)
            let categoriesData: [(UUID, PlatformType)] = [
                (UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!, .youtube),
                (UUID(uuidString: "00000000-0000-0000-0000-0000000000C2")!, .instagram),
                (UUID(uuidString: "00000000-0000-0000-0000-0000000000C3")!, .tiktok),
                (UUID(uuidString: "00000000-0000-0000-0000-0000000000C4")!, .facebook),
                (UUID(uuidString: "00000000-0000-0000-0000-0000000000C5")!, .email),
                (UUID(uuidString: "00000000-0000-0000-0000-0000000000C6")!, .shopeeAffiliate),
                (UUID(uuidString: "00000000-0000-0000-0000-0000000000C7")!, .googleAdSense),
                (UUID(uuidString: "00000000-0000-0000-0000-0000000000C8")!, .websiteDomain)
            ]

            var categoryMap: [String: PlatformCategory] = [:]
            for (catUUID, platform) in categoriesData {
                let category = PlatformCategory(
                    id: catUUID,
                    name: platform.rawValue,
                    iconName: platform.iconName,
                    displayOrder: platform.defaultOrder,
                    isDefault: true,
                    createdAt: Self.baseDate,
                    updatedAt: Self.baseDate
                )
                context.insert(category)
                categoryMap[platform.rawValue] = category
            }

            // Custom Category: Creator Tools (isDefault = false, displayOrder = 9)
            let customCategory = PlatformCategory(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C9")!,
                name: "Creator Tools",
                iconName: "wrench.and.screwdriver",
                displayOrder: 9,
                isDefault: false,
                createdAt: Self.baseDate,
                updatedAt: Self.baseDate
            )
            context.insert(customCategory)

            // 5. Account 1: YouTube (Active, Populated — 2 Details, 4 Logs)
            let ytAcc = Account(
                id: UUID(uuidString: "00000000-0000-0000-0001-000000000001")!,
                name: "Aruna Studio Official",
                platform: PlatformType.youtube.rawValue,
                username: "arunastudio",
                emailReference: "contact@arunastudio.example.com",
                profileURLString: "https://youtube.com/@arunastudio",
                officialDashboardURLString: "https://studio.youtube.com",
                accountType: .creator,
                accountStatus: .active,
                monetizationStatus: .monetized,
                notes: """
                Primary production studio channel.
                Runbook:
                - Upload 4K ProRes masters via gigabit uplink
                - Review community guidelines quarterly
                """,
                isArchived: false,
                creationDate: Self.baseDate.addingTimeInterval(-86400 * 365),
                lastCheckedDate: Self.baseDate,
                domainExpirationDate: nil,
                createdAt: Self.baseDate,
                updatedAt: Self.baseDate,
                category: customCategory
            )
            context.insert(ytAcc)

            // Child relationships configured purely via child.account (Single-direction anchor, no double append)
            let ytDetail1 = AccountDetail(
                id: UUID(uuidString: "00000000-0000-0000-0002-000000000001")!,
                key: "platform.youtube.channel_id",
                value: "UC_arunastudio_example_id",
                createdAt: Self.baseDate,
                updatedAt: Self.baseDate,
                account: ytAcc
            )
            context.insert(ytDetail1)

            let ytDetail2 = AccountDetail(
                id: UUID(uuidString: "00000000-0000-0000-0002-000000000002")!,
                key: "monetization.payout.currency",
                value: "USD",
                createdAt: Self.baseDate,
                updatedAt: Self.baseDate,
                account: ytAcc
            )
            context.insert(ytDetail2)

            let ytLogs = [
                ActivityLog(
                    id: UUID(uuidString: "00000000-0000-0000-0003-000000000001")!,
                    actionType: "Created",
                    details: "Account registered in vault under platform 'YouTube'",
                    timestamp: Self.baseDate.addingTimeInterval(10),
                    sequenceNumber: 1,
                    createdAt: Self.baseDate.addingTimeInterval(10),
                    updatedAt: Self.baseDate.addingTimeInterval(10),
                    account: ytAcc
                ),
                ActivityLog(
                    id: UUID(uuidString: "00000000-0000-0000-0003-000000000002")!,
                    actionType: "Detail Added",
                    details: "Added metadata 'platform.youtube.channel_id'",
                    timestamp: Self.baseDate.addingTimeInterval(20),
                    sequenceNumber: 2,
                    createdAt: Self.baseDate.addingTimeInterval(20),
                    updatedAt: Self.baseDate.addingTimeInterval(20),
                    account: ytAcc
                ),
                ActivityLog(
                    id: UUID(uuidString: "00000000-0000-0000-0003-000000000003")!,
                    actionType: "Detail Added",
                    details: "Added metadata 'monetization.payout.currency'",
                    timestamp: Self.baseDate.addingTimeInterval(30),
                    sequenceNumber: 3,
                    createdAt: Self.baseDate.addingTimeInterval(30),
                    updatedAt: Self.baseDate.addingTimeInterval(30),
                    account: ytAcc
                ),
                ActivityLog(
                    id: UUID(uuidString: "00000000-0000-0000-0003-000000000004")!,
                    actionType: "Status Checked",
                    details: "Manual account status check recorded",
                    timestamp: Self.baseDate.addingTimeInterval(40),
                    sequenceNumber: 4,
                    createdAt: Self.baseDate.addingTimeInterval(40),
                    updatedAt: Self.baseDate.addingTimeInterval(40),
                    account: ytAcc
                )
            ]
            for log in ytLogs {
                context.insert(log)
            }

            // 6. Account 2: Instagram (Active, Populated — 1 Detail, 2 Logs)
            let igAcc = Account(
                id: UUID(uuidString: "00000000-0000-0000-0001-000000000002")!,
                name: "Batik Modern Store",
                platform: PlatformType.instagram.rawValue,
                username: "batikmodern_id",
                emailReference: "marketing@batikmodern.example.com",
                profileURLString: "https://www.instagram.com/batikmodern_id",
                officialDashboardURLString: "",
                accountType: .brand,
                accountStatus: .active,
                monetizationStatus: .eligible,
                notes: "Retail catalog and branding account.",
                isArchived: false,
                creationDate: Self.baseDate.addingTimeInterval(-86400 * 180),
                lastCheckedDate: Self.baseDate,
                domainExpirationDate: nil,
                createdAt: Self.baseDate,
                updatedAt: Self.baseDate,
                category: categoryMap[PlatformType.instagram.rawValue]
            )
            context.insert(igAcc)

            let igDetail1 = AccountDetail(
                id: UUID(uuidString: "00000000-0000-0000-0002-000000000003")!,
                key: "platform.meta.page_id",
                value: "PAGE_1092837465",
                createdAt: Self.baseDate,
                updatedAt: Self.baseDate,
                account: igAcc
            )
            context.insert(igDetail1)

            let igLogs = [
                ActivityLog(
                    id: UUID(uuidString: "00000000-0000-0000-0003-000000000005")!,
                    actionType: "Created",
                    details: "Account registered in vault under platform 'Instagram'",
                    timestamp: Self.baseDate.addingTimeInterval(50),
                    sequenceNumber: 1,
                    createdAt: Self.baseDate.addingTimeInterval(50),
                    updatedAt: Self.baseDate.addingTimeInterval(50),
                    account: igAcc
                ),
                ActivityLog(
                    id: UUID(uuidString: "00000000-0000-0000-0003-000000000006")!,
                    actionType: "Detail Added",
                    details: "Added metadata 'platform.meta.page_id'",
                    timestamp: Self.baseDate.addingTimeInterval(60),
                    sequenceNumber: 2,
                    createdAt: Self.baseDate.addingTimeInterval(60),
                    updatedAt: Self.baseDate.addingTimeInterval(60),
                    account: igAcc
                )
            ]
            for log in igLogs {
                context.insert(log)
            }

            // 7. Account 3: Website & Domain (Active, With Expiration Date — 3 Details, 4 Logs)
            let domainAcc = Account(
                id: UUID(uuidString: "00000000-0000-0000-0001-000000000003")!,
                name: "Nusantara Portal Web",
                platform: PlatformType.websiteDomain.rawValue,
                username: "nusantaraportal.example",
                emailReference: "noc@nusantaraportal.example",
                profileURLString: "https://nusantaraportal.example",
                officialDashboardURLString: "https://dash.cloudflare.com",
                accountType: .administrative,
                accountStatus: .active,
                monetizationStatus: .notApplicable,
                notes: """
                Authoritative edge portal routing infrastructure.
                Domain registered via Cloudflare Registrar.
                Primary nameservers: ns1.cloudflare.com, ns2.cloudflare.com.
                """,
                isArchived: false,
                creationDate: Self.baseDate.addingTimeInterval(-86400 * 500),
                lastCheckedDate: Self.baseDate,
                domainExpirationDate: Self.domainExpDate,
                createdAt: Self.baseDate,
                updatedAt: Self.baseDate,
                category: categoryMap[PlatformType.websiteDomain.rawValue]
            )
            context.insert(domainAcc)

            let dDetails = [
                AccountDetail(
                    id: UUID(uuidString: "00000000-0000-0000-0002-000000000004")!,
                    key: "infrastructure.cloudflare.zone_id",
                    value: "ZONE_abcdef0123456789",
                    createdAt: Self.baseDate,
                    updatedAt: Self.baseDate,
                    account: domainAcc
                ),
                AccountDetail(
                    id: UUID(uuidString: "00000000-0000-0000-0002-000000000005")!,
                    key: "infrastructure.dns.nameserver_1",
                    value: "ns1.exampledns.net",
                    createdAt: Self.baseDate,
                    updatedAt: Self.baseDate,
                    account: domainAcc
                ),
                AccountDetail(
                    id: UUID(uuidString: "00000000-0000-0000-0002-000000000006")!,
                    key: "infrastructure.dns.nameserver_2",
                    value: "ns2.exampledns.net",
                    createdAt: Self.baseDate,
                    updatedAt: Self.baseDate,
                    account: domainAcc
                )
            ]
            for detail in dDetails {
                context.insert(detail)
            }

            let domainLogs = [
                ActivityLog(
                    id: UUID(uuidString: "00000000-0000-0000-0003-000000000007")!,
                    actionType: "Created",
                    details: "Account registered in vault under platform 'Website & Domain'",
                    timestamp: Self.baseDate.addingTimeInterval(70),
                    sequenceNumber: 1,
                    createdAt: Self.baseDate.addingTimeInterval(70),
                    updatedAt: Self.baseDate.addingTimeInterval(70),
                    account: domainAcc
                ),
                ActivityLog(
                    id: UUID(uuidString: "00000000-0000-0000-0003-000000000008")!,
                    actionType: "Detail Added",
                    details: "Added metadata 'infrastructure.cloudflare.zone_id'",
                    timestamp: Self.baseDate.addingTimeInterval(80),
                    sequenceNumber: 2,
                    createdAt: Self.baseDate.addingTimeInterval(80),
                    updatedAt: Self.baseDate.addingTimeInterval(80),
                    account: domainAcc
                ),
                ActivityLog(
                    id: UUID(uuidString: "00000000-0000-0000-0003-000000000009")!,
                    actionType: "Detail Added",
                    details: "Added metadata 'infrastructure.dns.nameserver_1'",
                    timestamp: Self.baseDate.addingTimeInterval(90),
                    sequenceNumber: 3,
                    createdAt: Self.baseDate.addingTimeInterval(90),
                    updatedAt: Self.baseDate.addingTimeInterval(90),
                    account: domainAcc
                ),
                ActivityLog(
                    id: UUID(uuidString: "00000000-0000-0000-0003-000000000010")!,
                    actionType: "Detail Added",
                    details: "Added metadata 'infrastructure.dns.nameserver_2'",
                    timestamp: Self.baseDate.addingTimeInterval(100),
                    sequenceNumber: 4,
                    createdAt: Self.baseDate.addingTimeInterval(100),
                    updatedAt: Self.baseDate.addingTimeInterval(100),
                    account: domainAcc
                )
            ]
            for log in domainLogs {
                context.insert(log)
            }

            // 8. Account 4: Shopee Affiliate (Active, Populated — 1 Detail, 2 Logs)
            let affAcc = Account(
                id: UUID(uuidString: "00000000-0000-0000-0001-000000000004")!,
                name: "Gadget Reviewer Affiliate",
                platform: PlatformType.shopeeAffiliate.rawValue,
                username: "gadgetdeals_id",
                emailReference: "affiliate@gadgetdeals.example.com",
                profileURLString: "",
                officialDashboardURLString: "https://affiliate.shopee.co.id",
                accountType: .affiliate,
                accountStatus: .active,
                monetizationStatus: .monetized,
                notes: "Consumer tech affiliate conversion tracking.",
                isArchived: false,
                creationDate: Self.baseDate.addingTimeInterval(-86400 * 90),
                lastCheckedDate: Self.baseDate,
                domainExpirationDate: nil,
                createdAt: Self.baseDate,
                updatedAt: Self.baseDate,
                category: categoryMap[PlatformType.shopeeAffiliate.rawValue]
            )
            context.insert(affAcc)

            let affDetail1 = AccountDetail(
                id: UUID(uuidString: "00000000-0000-0000-0002-000000000007")!,
                key: "monetization.payout.currency",
                value: "IDR",
                createdAt: Self.baseDate,
                updatedAt: Self.baseDate,
                account: affAcc
            )
            context.insert(affDetail1)

            let affLogs = [
                ActivityLog(
                    id: UUID(uuidString: "00000000-0000-0000-0003-000000000011")!,
                    actionType: "Created",
                    details: "Account registered in vault under platform 'Shopee Affiliate'",
                    timestamp: Self.baseDate.addingTimeInterval(110),
                    sequenceNumber: 1,
                    createdAt: Self.baseDate.addingTimeInterval(110),
                    updatedAt: Self.baseDate.addingTimeInterval(110),
                    account: affAcc
                ),
                ActivityLog(
                    id: UUID(uuidString: "00000000-0000-0000-0003-000000000012")!,
                    actionType: "Detail Added",
                    details: "Added metadata 'monetization.payout.currency'",
                    timestamp: Self.baseDate.addingTimeInterval(120),
                    sequenceNumber: 2,
                    createdAt: Self.baseDate.addingTimeInterval(120),
                    updatedAt: Self.baseDate.addingTimeInterval(120),
                    account: affAcc
                )
            ]
            for log in affLogs {
                context.insert(log)
            }

            // 9. Account 5: Email (Archived, Minimal / Nil fields — 0 Details, 2 Logs)
            let mailAcc = Account(
                id: UUID(uuidString: "00000000-0000-0000-0001-000000000005")!,
                name: "Legacy Internal Ops Mail",
                platform: PlatformType.email.rawValue,
                username: "",
                emailReference: "",
                profileURLString: "",
                officialDashboardURLString: "",
                accountType: .personal,
                accountStatus: .inactive,
                monetizationStatus: .notApplicable,
                notes: "",
                isArchived: true,
                creationDate: Self.baseDate.addingTimeInterval(-86400 * 700),
                lastCheckedDate: Self.baseDate,
                domainExpirationDate: nil,
                createdAt: Self.baseDate,
                updatedAt: Self.baseDate,
                category: nil
            )
            context.insert(mailAcc)

            let mailLogs = [
                ActivityLog(
                    id: UUID(uuidString: "00000000-0000-0000-0003-000000000013")!,
                    actionType: "Created",
                    details: "Account registered in vault under platform 'Email'",
                    timestamp: Self.baseDate.addingTimeInterval(130),
                    sequenceNumber: 1,
                    createdAt: Self.baseDate.addingTimeInterval(130),
                    updatedAt: Self.baseDate.addingTimeInterval(130),
                    account: mailAcc
                ),
                ActivityLog(
                    id: UUID(uuidString: "00000000-0000-0000-0003-000000000014")!,
                    actionType: "Archived",
                    details: "Account moved to archive",
                    timestamp: Self.baseDate.addingTimeInterval(140),
                    sequenceNumber: 2,
                    createdAt: Self.baseDate.addingTimeInterval(140),
                    updatedAt: Self.baseDate.addingTimeInterval(140),
                    account: mailAcc
                )
            ]
            for log in mailLogs {
                context.insert(log)
            }

            try context.save()
        }() // ModelContainer and ModelContext deallocated here

        // 10. Post-Generation WAL Checkpoint, Integrity Check & Read-Back Verification
        try Self.performWALCheckpoint(at: basePath)
        try Self.verifyDatabaseIntegrity(at: basePath)
        try Self.verifyPostGenerationFixture(at: basePath)

        print("[FIXTURE GENERATOR] SUCCESS: v1_migration_fixture.sqlite generated and verified at: \(basePath)")
    }

    // MARK: - Project Root Ancestor Discovery

    /// Discovers the project root directory by traversing upwards through ancestors
    /// and verifying the presence of both `Package.swift` and `Tests/SocialAccountVaultTests`.
    private static func findProjectRoot() throws -> URL {
        let fileManager = FileManager.default

        // Candidate start locations:
        // 1. Directory containing this file (#filePath, guaranteed absolute on Swift 5.8+)
        // 2. Directory containing this file (#file, which may be relative or concise)
        // 3. Process current working directory
        var candidateStartDirs: [URL] = []

        let filePathURL = URL(fileURLWithPath: #filePath).standardizedFileURL
        candidateStartDirs.append(filePathURL.deletingLastPathComponent())

        let fileURL = URL(fileURLWithPath: #file).standardizedFileURL
        candidateStartDirs.append(fileURL.deletingLastPathComponent())

        let cwdURL = URL(fileURLWithPath: fileManager.currentDirectoryPath).standardizedFileURL
        candidateStartDirs.append(cwdURL)

        for startDir in candidateStartDirs {
            var currentDir = startDir
            while true {
                let packageSwiftPath = currentDir.appendingPathComponent("Package.swift").path
                let testDirURL = currentDir.appendingPathComponent("Tests/SocialAccountVaultTests")
                var isTestDir: ObjCBool = false

                if fileManager.fileExists(atPath: packageSwiftPath) &&
                   fileManager.fileExists(atPath: testDirURL.path, isDirectory: &isTestDir) &&
                   isTestDir.boolValue {
                    return currentDir.standardizedFileURL
                }

                let parentDir = currentDir.deletingLastPathComponent()
                if parentDir.path == currentDir.path {
                    // Reached filesystem root for this candidate branch
                    break
                }
                currentDir = parentDir
            }
        }

        throw FixtureGenerationError.readBackFailed(
            "Cannot determine SocialAccountVault repository root. Traversed upwards from #filePath, #file, and cwd, but could not find an ancestor containing both 'Package.swift' and 'Tests/SocialAccountVaultTests'."
        )
    }

    // MARK: - SQLite C API Scoped Resource Managers

    /// Executes a block with an open SQLite database connection, ensuring leak-free and checked cleanup.
    private static func withSQLiteConnection<T>(
        at path: String,
        flags: Int32,
        _ body: (OpaquePointer) throws -> T
    ) throws -> T {
        var db: OpaquePointer?
        let openRC = sqlite3_open_v2(path, &db, flags, nil)
        guard openRC == SQLITE_OK, let validDb = db else {
            let errMsg: String
            if let db = db {
                errMsg = String(cString: sqlite3_errmsg(db))
                let closeRC = sqlite3_close(db)
                if closeRC != SQLITE_OK {
                    _ = sqlite3_close_v2(db) // Fallback zombie deallocation to mitigate leaked handle
                    throw FixtureGenerationError.sqliteConnectionFailed(
                        "sqlite3_open_v2 failed (\(openRC): \(errMsg)) and cleanup sqlite3_close failed with code: \(closeRC)"
                    )
                }
            } else {
                errMsg = "Code \(openRC)"
            }
            throw FixtureGenerationError.sqliteConnectionFailed("sqlite3_open_v2 failed: \(errMsg)")
        }

        let bodyResult: Result<T, Error>
        do {
            bodyResult = .success(try body(validDb))
        } catch {
            bodyResult = .failure(error)
        }

        let closeRC = sqlite3_close(validDb)

        switch bodyResult {
        case .success(let value):
            guard closeRC == SQLITE_OK else {
                // If sqlite3_close returns SQLITE_BUSY (code 5) or another failure code,
                // unfinalized statements or open transactions still hold locks.
                // We trigger sqlite3_close_v2 as a destructor fallback, but refuse to claim success.
                let fallbackRC = sqlite3_close_v2(validDb)
                throw FixtureGenerationError.sqliteConnectionFailed(
                    "sqlite3_close failed after execution with code: \(closeRC) (SQLITE_BUSY=\(closeRC == SQLITE_BUSY), close_v2_fallback=\(fallbackRC == SQLITE_OK))"
                )
            }
            return value

        case .failure(let bodyError):
            if closeRC != SQLITE_OK {
                let fallbackRC = sqlite3_close_v2(validDb)
                throw FixtureGenerationError.sqliteConnectionFailed(
                    "Execution failed with '\(bodyError.localizedDescription)' and cleanup sqlite3_close failed with code: \(closeRC) (SQLITE_BUSY=\(closeRC == SQLITE_BUSY), close_v2_fallback=\(fallbackRC == SQLITE_OK))"
                )
            }
            throw bodyError
        }
    }

    /// Executes a block with a prepared SQLite statement, ensuring leak-free and checked finalization.
    private static func withPreparedStatement<T>(
        db: OpaquePointer,
        sql: String,
        _ body: (OpaquePointer) throws -> T
    ) throws -> T {
        var stmt: OpaquePointer?
        let prepRC = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard prepRC == SQLITE_OK, let validStmt = stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            if let stmt = stmt {
                let finRC = sqlite3_finalize(stmt)
                if finRC != SQLITE_OK {
                    print("[FIXTURE GENERATOR] Statement cleanup after prepare failure for '\(sql)': sqlite3_finalize echoed status code \(finRC)")
                }
            }
            throw FixtureGenerationError.backupCorrupted("sqlite3_prepare_v2 failed for '\(sql)': \(msg)")
        }

        let bodyResult: Result<T, Error>
        do {
            bodyResult = .success(try body(validStmt))
        } catch {
            bodyResult = .failure(error)
        }

        let finRC = sqlite3_finalize(validStmt)

        switch bodyResult {
        case .success(let value):
            guard finRC == SQLITE_OK else {
                throw FixtureGenerationError.backupCorrupted("sqlite3_finalize failed for '\(sql)' with code: \(finRC)")
            }
            return value

        case .failure(let bodyError):
            // Per SQLite C API specification: sqlite3_finalize() always frees statement memory,
            // but returns the result code of the most recent evaluation (e.g. from sqlite3_step).
            // When body fails, finRC != SQLITE_OK reflects the evaluation error rather than a failure
            // to finalize. We maintain bodyError as the primary error and record finRC as cleanup diagnostics.
            if finRC != SQLITE_OK {
                print("[FIXTURE GENERATOR] Statement cleanup for '\(sql)': sqlite3_finalize echoed execution status code \(finRC)")
            }
            throw bodyError
        }
    }

    // MARK: - SQLite C API Lifecycle & Integrity Helpers

    private static func readDatabaseHeaderFormatVersion(at path: String) -> (writeVersion: UInt8, readVersion: UInt8)? {
        guard let fileHandle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? fileHandle.close() }
        do {
            try fileHandle.seek(toOffset: 18)
            guard let data = try fileHandle.read(upToCount: 2), data.count == 2 else { return nil }
            return (data[0], data[1])
        } catch {
            return nil
        }
    }

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Performs a consistent, transactional SQLite VACUUM INTO backup from source to destination.
    /// Creates a 100% self-contained, standalone single-file SQLite database in rollback journal mode (DELETE)
    /// with file header format version 1 (bytes 18-19 = 0x01 0x01).
    /// Does NOT create or leave any companion sidecar files (-wal / -shm).
    private static func performVacuumBackup(
        from sourcePath: String,
        to destinationPath: String,
        sourceFlags: Int32 = SQLITE_OPEN_READONLY
    ) throws {
        let fm = FileManager.default

        // Destination file must not already exist to prevent accidental overwrite or destruction of existing data
        guard !fm.fileExists(atPath: destinationPath) else {
            throw FixtureGenerationError.backupFailed(
                "Destination backup file already exists at '\(destinationPath)'. Operation aborted to prevent overwriting."
            )
        }

        // Open source database using specified flags (default SQLITE_OPEN_READONLY, or SQLITE_OPEN_READWRITE if shared-memory initialization is required).
        try withSQLiteConnection(at: sourcePath, flags: sourceFlags) { db in
            // Guard against running inside an active transaction (VACUUM cannot be run inside a transaction)
            guard sqlite3_get_autocommit(db) != 0 else {
                throw FixtureGenerationError.backupCorrupted("Cannot execute VACUUM INTO inside an active transaction")
            }

            var pStmt: OpaquePointer?
            let sql = "VACUUM INTO ?;"
            let prepRC = sqlite3_prepare_v2(db, sql, -1, &pStmt, nil)
            guard prepRC == SQLITE_OK, let stmt = pStmt else {
                let errMsg = String(cString: sqlite3_errmsg(db))
                let extCode = sqlite3_extended_errcode(db)
                throw FixtureGenerationError.backupCorrupted("prepare VACUUM INTO failed with code \(prepRC) (extended: \(extCode)): \(errMsg)")
            }

            // Bind destination path as parameter 1 using sqlite3_bind_text (no string interpolation)
            let bindRC = sqlite3_bind_text(stmt, 1, destinationPath, -1, sqliteTransient)
            guard bindRC == SQLITE_OK else {
                sqlite3_finalize(stmt)
                let errMsg = String(cString: sqlite3_errmsg(db))
                let extCode = sqlite3_extended_errcode(db)
                throw FixtureGenerationError.backupCorrupted("bind destination path to VACUUM INTO failed with code \(bindRC) (extended: \(extCode)): \(errMsg)")
            }

            let stepRC = sqlite3_step(stmt)
            let errMsgBeforeFinalize = String(cString: sqlite3_errmsg(db))
            let extCodeBeforeFinalize = sqlite3_extended_errcode(db)
            let finRC = sqlite3_finalize(stmt)

            guard stepRC == SQLITE_DONE else {
                throw FixtureGenerationError.backupCorrupted(
                    "sqlite3_step on VACUUM INTO failed with code: \(stepRC) (extended: \(extCodeBeforeFinalize), finalize: \(finRC)): \(errMsgBeforeFinalize)"
                )
            }

            guard finRC == SQLITE_OK else {
                let errMsg = String(cString: sqlite3_errmsg(db))
                throw FixtureGenerationError.backupCorrupted("sqlite3_finalize on VACUUM INTO failed with code: \(finRC): \(errMsg)")
            }
        }
    }

    /// Performs a consistent, transactional SQLite Online Backup from source to destination.
    /// Converts the destination database to `PRAGMA journal_mode = DELETE` so that it becomes
    /// a 100% self-contained single file that can be opened and verified via `SQLITE_OPEN_READONLY`
    /// without requiring companion `-wal` or `-shm` files.
    private static func performOnlineBackup(from sourcePath: String, to destinationPath: String) throws {
        let fm = FileManager.default

        func logBackupState(_ step: String) {
            let dbExists = fm.fileExists(atPath: destinationPath)
            let shmExists = fm.fileExists(atPath: "\(destinationPath)-shm")
            let walExists = fm.fileExists(atPath: "\(destinationPath)-wal")
            print("[DIAGNOSTIC BACKUP - \(step)] db: \(dbExists), shm: \(shmExists), wal: \(walExists)")
        }

        func logHeaderBytes(_ stage: String) {
            if let versions = readDatabaseHeaderFormatVersion(at: destinationPath) {
                print("[DIAGNOSTIC HEADER - \(stage)] writeVersion (byte 18): \(versions.writeVersion), readVersion (byte 19): \(versions.readVersion)")
            } else {
                print("[DIAGNOSTIC HEADER - \(stage)] unable to read header bytes 18-19")
            }
        }

        logBackupState("0. Initial State (before opening)")

        // Open source in READONLY mode
        try withSQLiteConnection(at: sourcePath, flags: SQLITE_OPEN_READONLY) { srcDb in
            var srcMode = "unknown"
            try withPreparedStatement(db: srcDb, sql: "PRAGMA journal_mode;") { stmt in
                if sqlite3_step(stmt) == SQLITE_ROW, let ptr = sqlite3_column_text(stmt, 0) {
                    srcMode = String(cString: ptr)
                }
            }
            print("[DIAGNOSTIC BACKUP] Source journal_mode: '\(srcMode)'")

            // Open destination in READWRITE | CREATE mode
            try withSQLiteConnection(at: destinationPath, flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE) { dstDb in
                logBackupState("1. Destination Connection Opened")

                guard let backup = sqlite3_backup_init(dstDb, "main", srcDb, "main") else {
                    let errMsg = String(cString: sqlite3_errmsg(dstDb))
                    throw FixtureGenerationError.backupCorrupted("sqlite3_backup_init failed: \(errMsg)")
                }
                logBackupState("2. After sqlite3_backup_init")

                var stepRC: Int32 = SQLITE_OK
                var retryCount = 0
                let maxRetries = 5

                repeat {
                    stepRC = sqlite3_backup_step(backup, -1) // -1 copies all pages in single/remaining step
                    if stepRC == SQLITE_BUSY || stepRC == SQLITE_LOCKED {
                        retryCount += 1
                        if retryCount > maxRetries {
                            break
                        }
                        sqlite3_sleep(25)
                    }
                } while stepRC == SQLITE_BUSY || stepRC == SQLITE_LOCKED

                logBackupState("3. After sqlite3_backup_step (code: \(stepRC))")

                let finishRC = sqlite3_backup_finish(backup)
                logBackupState("4. After sqlite3_backup_finish (code: \(finishRC))")
                logHeaderBytes("After sqlite3_backup_finish")

                guard stepRC == SQLITE_DONE else {
                    let errMsg = String(cString: sqlite3_errmsg(dstDb))
                    throw FixtureGenerationError.backupCorrupted(
                        "sqlite3_backup_step failed with code: \(stepRC) (finishRC: \(finishRC)): \(errMsg)"
                    )
                }

                guard finishRC == SQLITE_OK else {
                    let errMsg = String(cString: sqlite3_errmsg(dstDb))
                    throw FixtureGenerationError.backupCorrupted(
                        "sqlite3_backup_finish failed with code: \(finishRC): \(errMsg)"
                    )
                }

                // Granular PRAGMA journal_mode = DELETE execution & diagnostics:
                // 1a. Sebelum sqlite3_prepare_v2
                logBackupState("5a. Before sqlite3_prepare_v2(PRAGMA journal_mode = DELETE)")

                var pStmt: OpaquePointer?
                let prepRC = sqlite3_prepare_v2(dstDb, "PRAGMA journal_mode = DELETE;", -1, &pStmt, nil)
                guard prepRC == SQLITE_OK, let stmt = pStmt else {
                    let errMsg = String(cString: sqlite3_errmsg(dstDb))
                    throw FixtureGenerationError.backupCorrupted("prepare PRAGMA journal_mode = DELETE failed (\(prepRC)): \(errMsg)")
                }

                // 1b. Setelah prepare sebelum step
                logBackupState("5b. After prepare, before sqlite3_step")

                let jStep = sqlite3_step(stmt)
                var resultingMode = "unknown"
                if let ptr = sqlite3_column_text(stmt, 0) {
                    resultingMode = String(cString: ptr)
                }
                print("[DIAGNOSTIC BACKUP] PRAGMA journal_mode = DELETE step code: \(jStep), returned text: '\(resultingMode)'")

                // 1c. Setelah sqlite3_step tetapi sebelum finalize
                logBackupState("5c. After sqlite3_step, before finalize")

                let finRC = sqlite3_finalize(stmt)
                print("[DIAGNOSTIC BACKUP] sqlite3_finalize code: \(finRC)")

                // 1d. Setelah finalize
                logBackupState("5d. After finalize")
                logHeaderBytes("After PRAGMA journal_mode = DELETE finalized")

                guard jStep == SQLITE_ROW else {
                    throw FixtureGenerationError.backupCorrupted("Setting PRAGMA journal_mode = DELETE returned unexpected step code: \(jStep)")
                }
                guard finRC == SQLITE_OK else {
                    throw FixtureGenerationError.backupCorrupted("Finalizing PRAGMA journal_mode = DELETE failed with code: \(finRC)")
                }
                guard resultingMode.lowercased() == "delete" else {
                    throw FixtureGenerationError.backupCorrupted(
                        "PRAGMA journal_mode = DELETE failed to switch mode, current mode: '\(resultingMode)'"
                    )
                }
            }
            // 1e. Setelah dstDb ditutup
            logBackupState("5e. After dstDb Closed")
        }
        // 1f. Setelah srcDb ditutup
        logBackupState("5f. After srcDb Closed (All Backup Connections Terminated)")
        logHeaderBytes("After all connections closed")

        // 6. Orphaned sidecar cleanup (minimal fix).
        // After PRAGMA journal_mode = DELETE and ALL connections are closed, the destination
        // header is format version 1 (rollback journal). SQLite may still leave an orphaned
        // -shm file on disk (macOS does not always unlink it on the WAL->DELETE transition).
        // Remove leftover -shm / -wal ONLY when the header confirms rollback mode (1/1), so a
        // live WAL database's sidecars are never touched. This guarantees a standalone single file.
        if let versions = readDatabaseHeaderFormatVersion(at: destinationPath),
           versions.writeVersion == 1, versions.readVersion == 1 {
            for sidecar in ["\(destinationPath)-shm", "\(destinationPath)-wal"] where fm.fileExists(atPath: sidecar) {
                try fm.removeItem(atPath: sidecar)
            }
        }
        logBackupState("6. After orphaned sidecar cleanup")
    }

    private static func performWALCheckpoint(at path: String) throws {
        try withSQLiteConnection(at: path, flags: SQLITE_OPEN_READWRITE) { db in
            var logSize: Int32 = 0
            var checkpointCount: Int32 = 0
            let checkpointRC = sqlite3_wal_checkpoint_v2(db, nil, SQLITE_CHECKPOINT_TRUNCATE, &logSize, &checkpointCount)
            guard checkpointRC == SQLITE_OK else {
                throw FixtureGenerationError.checkpointFailed(
                    "sqlite3_wal_checkpoint_v2 failed with code: \(checkpointRC), logSize: \(logSize), checkpointCount: \(checkpointCount)"
                )
            }
        }
    }

    private static func verifyDatabaseIntegrity(at path: String) throws {
        try withSQLiteConnection(at: path, flags: SQLITE_OPEN_READONLY) { db in
            // 1. PRAGMA integrity_check: must return exactly one row "ok" then SQLITE_DONE
            try withPreparedStatement(db: db, sql: "PRAGMA integrity_check;") { stmt in
                let step1 = sqlite3_step(stmt)
                guard step1 == SQLITE_ROW else {
                    throw FixtureGenerationError.backupCorrupted("PRAGMA integrity_check returned no rows (code: \(step1))")
                }

                guard let textPtr = sqlite3_column_text(stmt, 0) else {
                    throw FixtureGenerationError.backupCorrupted("PRAGMA integrity_check returned NULL text")
                }
                let resultText = String(cString: textPtr)
                guard resultText == "ok" else {
                    throw FixtureGenerationError.backupCorrupted("PRAGMA integrity_check returned: '\(resultText)'")
                }

                let step2 = sqlite3_step(stmt)
                guard step2 == SQLITE_DONE else {
                    throw FixtureGenerationError.backupCorrupted("PRAGMA integrity_check returned multiple rows (code: \(step2))")
                }
            }

            // 2. PRAGMA foreign_key_check: must return 0 rows (immediate SQLITE_DONE)
            try withPreparedStatement(db: db, sql: "PRAGMA foreign_key_check;") { stmt in
                let stepRC = sqlite3_step(stmt)
                guard stepRC == SQLITE_DONE else {
                    throw FixtureGenerationError.backupCorrupted("PRAGMA foreign_key_check detected violations (code: \(stepRC))")
                }
            }
        }
    }

    // MARK: - Post-Generation Disk Verification

    private static func verifyPostGenerationFixture(at path: String) throws {
        try withSQLiteConnection(at: path, flags: SQLITE_OPEN_READONLY) { db in

            // Scalar Integer Query Helper with checked statement lifecycle
            func queryInt(_ sql: String) throws -> Int {
                return try withPreparedStatement(db: db, sql: sql) { stmt in
                    let stepRC = sqlite3_step(stmt)
                    guard stepRC == SQLITE_ROW else {
                        throw FixtureGenerationError.readBackFailed("No row returned for '\(sql)' (step code: \(stepRC))")
                    }

                    let val = Int(sqlite3_column_int64(stmt, 0))

                    let doneRC = sqlite3_step(stmt)
                    guard doneRC == SQLITE_DONE else {
                        throw FixtureGenerationError.readBackFailed(
                            "Multiple rows returned for scalar query '\(sql)' (done code: \(doneRC))"
                        )
                    }
                    return val
                }
            }

            // UUID Extractor Helper supporting both TEXT and 16-byte BLOB storage
            func queryUUIDs(table: String) throws -> [UUID] {
                let sql = "SELECT ZID FROM \(table);"
                return try withPreparedStatement(db: db, sql: sql) { stmt in
                    var uuids: [UUID] = []
                    while true {
                        let stepRC = sqlite3_step(stmt)
                        if stepRC == SQLITE_ROW {
                            let colType = sqlite3_column_type(stmt, 0)
                            if colType == SQLITE_TEXT {
                                guard let textPtr = sqlite3_column_text(stmt, 0) else {
                                    throw FixtureGenerationError.readBackFailed(
                                        "sqlite3_column_text returned nil for SQLITE_TEXT ZID in \(table)"
                                    )
                                }
                                let str = String(cString: textPtr)
                                guard let u = UUID(uuidString: str) else {
                                    throw FixtureGenerationError.readBackFailed(
                                        "Unparsable UUID text '\(str)' in \(table)"
                                    )
                                }
                                uuids.append(u)
                            } else if colType == SQLITE_BLOB {
                                let byteCount = sqlite3_column_bytes(stmt, 0)
                                guard byteCount == 16, let blobPtr = sqlite3_column_blob(stmt, 0) else {
                                    throw FixtureGenerationError.readBackFailed(
                                        "Invalid UUID BLOB in \(table), expected 16 bytes but got: \(byteCount)"
                                    )
                                }
                                let rawUUID = blobPtr.bindMemory(to: uuid_t.self, capacity: 1).pointee
                                uuids.append(UUID(uuid: rawUUID))
                            } else {
                                throw FixtureGenerationError.readBackFailed(
                                    "Unexpected column type \(colType) for ZID in \(table)"
                                )
                            }
                        } else if stepRC == SQLITE_DONE {
                            break
                        } else {
                            let msg = String(cString: sqlite3_errmsg(db))
                            throw FixtureGenerationError.readBackFailed("Step failed for '\(sql)': \(msg) (code: \(stepRC))")
                        }
                    }
                    return uuids
                }
            }

            // 1. Record Counts Verification
            let catCount = try queryInt("SELECT count(*) FROM ZPLATFORMCATEGORY;")
            guard catCount == 9 else {
                throw FixtureGenerationError.readBackFailed("Category count mismatch: got \(catCount), expected 9")
            }

            let defaultCatCount = try queryInt("SELECT count(*) FROM ZPLATFORMCATEGORY WHERE ZISDEFAULT = 1;")
            guard defaultCatCount == 8 else {
                throw FixtureGenerationError.readBackFailed("Default category count mismatch: got \(defaultCatCount), expected 8")
            }

            let customCatCount = try queryInt("SELECT count(*) FROM ZPLATFORMCATEGORY WHERE ZISDEFAULT = 0;")
            guard customCatCount == 1 else {
                throw FixtureGenerationError.readBackFailed("Custom category count mismatch: got \(customCatCount), expected 1")
            }

            let creatorToolsCount = try queryInt("""
                SELECT count(*) FROM ZPLATFORMCATEGORY
                WHERE ZNAME = 'Creator Tools' AND ZDISPLAYORDER = 9 AND ZISDEFAULT = 0;
            """)
            guard creatorToolsCount == 1 else {
                throw FixtureGenerationError.readBackFailed("Custom category 'Creator Tools' (order 9, isDefault 0) verification failed")
            }

            let accCount = try queryInt("SELECT count(*) FROM ZACCOUNT;")
            guard accCount == 5 else {
                throw FixtureGenerationError.readBackFailed("Account count mismatch: got \(accCount), expected 5")
            }

            let activeCount = try queryInt("SELECT count(*) FROM ZACCOUNT WHERE ZISARCHIVED = 0;")
            guard activeCount == 4 else {
                throw FixtureGenerationError.readBackFailed("Active account mismatch: got \(activeCount), expected 4")
            }

            let archivedCount = try queryInt("SELECT count(*) FROM ZACCOUNT WHERE ZISARCHIVED = 1;")
            guard archivedCount == 1 else {
                throw FixtureGenerationError.readBackFailed("Archived account mismatch: got \(archivedCount), expected 1")
            }

            let detailCount = try queryInt("SELECT count(*) FROM ZACCOUNTDETAIL;")
            guard detailCount == 7 else {
                throw FixtureGenerationError.readBackFailed("Detail count mismatch: got \(detailCount), expected 7")
            }

            let logCount = try queryInt("SELECT count(*) FROM ZACTIVITYLOG;")
            guard logCount == 14 else {
                throw FixtureGenerationError.readBackFailed("ActivityLog count mismatch: got \(logCount), expected 14")
            }

            // Verify Aruna Studio Official links to custom category 'Creator Tools'
            let ytCatCheck = try queryInt("""
                SELECT count(*) FROM ZACCOUNT a
                JOIN ZPLATFORMCATEGORY c ON a.ZCATEGORY = c.Z_PK
                WHERE a.ZNAME = 'Aruna Studio Official' AND c.ZNAME = 'Creator Tools' AND c.ZISDEFAULT = 0;
            """)
            guard ytCatCheck == 1 else {
                throw FixtureGenerationError.readBackFailed("Aruna Studio Official must be linked to custom category 'Creator Tools'")
            }

            // Verify Legacy Internal Ops Mail has nil category (uncategorized)
            let uncategorizedCount = try queryInt("""
                SELECT count(*) FROM ZACCOUNT
                WHERE ZNAME = 'Legacy Internal Ops Mail' AND ZCATEGORY IS NULL;
            """)
            guard uncategorizedCount == 1 else {
                throw FixtureGenerationError.readBackFailed("Legacy Internal Ops Mail must have nil category")
            }

            // Verify optional field variations:
            // 2 accounts with empty dashboard URL (Batik Modern Store & Legacy Internal Ops Mail)
            let emptyDashboardCount = try queryInt("""
                SELECT count(*) FROM ZACCOUNT
                WHERE ZOFFICIALDASHBOARDURLSTRING = '' OR ZOFFICIALDASHBOARDURLSTRING IS NULL;
            """)
            guard emptyDashboardCount == 2 else {
                throw FixtureGenerationError.readBackFailed("Expected 2 accounts with empty dashboard URL, got \(emptyDashboardCount)")
            }

            // 2 accounts with empty profile URL (Gadget Reviewer Affiliate & Legacy Internal Ops Mail)
            let emptyProfileCount = try queryInt("""
                SELECT count(*) FROM ZACCOUNT
                WHERE ZPROFILEURLSTRING = '' OR ZPROFILEURLSTRING IS NULL;
            """)
            guard emptyProfileCount == 2 else {
                throw FixtureGenerationError.readBackFailed("Expected 2 accounts with empty profile URL, got \(emptyProfileCount)")
            }

            // 1 account with non-nil domainExpirationDate (Nusantara Portal Web)
            let domainExpCount = try queryInt("""
                SELECT count(*) FROM ZACCOUNT
                WHERE ZDOMAINEXPIRATIONDATE IS NOT NULL;
            """)
            guard domainExpCount == 1 else {
                throw FixtureGenerationError.readBackFailed("Expected 1 account with domainExpirationDate, got \(domainExpCount)")
            }

            // 2. Per-Account Child Distribution Verification
            let expectedDistribution: [(name: String, details: Int, logs: Int)] = [
                ("Aruna Studio Official", 2, 4),
                ("Batik Modern Store", 1, 2),
                ("Nusantara Portal Web", 3, 4),
                ("Gadget Reviewer Affiliate", 1, 2),
                ("Legacy Internal Ops Mail", 0, 2)
            ]

            for expected in expectedDistribution {
                let escapedName = expected.name.replacingOccurrences(of: "'", with: "''")
                let dCount = try queryInt("""
                    SELECT count(d.Z_PK) FROM ZACCOUNT a
                    LEFT JOIN ZACCOUNTDETAIL d ON d.ZACCOUNT = a.Z_PK
                    WHERE a.ZNAME = '\(escapedName)';
                """)
                guard dCount == expected.details else {
                    throw FixtureGenerationError.readBackFailed(
                        "Detail count mismatch for '\(expected.name)': got \(dCount), expected \(expected.details)"
                    )
                }

                let lCount = try queryInt("""
                    SELECT count(l.Z_PK) FROM ZACCOUNT a
                    LEFT JOIN ZACTIVITYLOG l ON l.ZACCOUNT = a.Z_PK
                    WHERE a.ZNAME = '\(escapedName)';
                """)
                guard lCount == expected.logs else {
                    throw FixtureGenerationError.readBackFailed(
                        "ActivityLog count mismatch for '\(expected.name)': got \(lCount), expected \(expected.logs)"
                    )
                }
            }

            // 3. Exact 35 Deterministic UUID Validation
            let expectedUUIDStrings: Set<String> = Set([
                // Categories (8 Default + 1 Custom)
                "00000000-0000-0000-0000-0000000000C1",
                "00000000-0000-0000-0000-0000000000C2",
                "00000000-0000-0000-0000-0000000000C3",
                "00000000-0000-0000-0000-0000000000C4",
                "00000000-0000-0000-0000-0000000000C5",
                "00000000-0000-0000-0000-0000000000C6",
                "00000000-0000-0000-0000-0000000000C7",
                "00000000-0000-0000-0000-0000000000C8",
                "00000000-0000-0000-0000-0000000000C9", // Custom Category: Creator Tools
                // Accounts (5)
                "00000000-0000-0000-0001-000000000001",
                "00000000-0000-0000-0001-000000000002",
                "00000000-0000-0000-0001-000000000003",
                "00000000-0000-0000-0001-000000000004",
                "00000000-0000-0000-0001-000000000005",
                // Details (7)
                "00000000-0000-0000-0002-000000000001",
                "00000000-0000-0000-0002-000000000002",
                "00000000-0000-0000-0002-000000000003",
                "00000000-0000-0000-0002-000000000004",
                "00000000-0000-0000-0002-000000000005",
                "00000000-0000-0000-0002-000000000006",
                "00000000-0000-0000-0002-000000000007",
                // ActivityLogs (14)
                "00000000-0000-0000-0003-000000000001",
                "00000000-0000-0000-0003-000000000002",
                "00000000-0000-0000-0003-000000000003",
                "00000000-0000-0000-0003-000000000004",
                "00000000-0000-0000-0003-000000000005",
                "00000000-0000-0000-0003-000000000006",
                "00000000-0000-0000-0003-000000000007",
                "00000000-0000-0000-0003-000000000008",
                "00000000-0000-0000-0003-000000000009",
                "00000000-0000-0000-0003-000000000010",
                "00000000-0000-0000-0003-000000000011",
                "00000000-0000-0000-0003-000000000012",
                "00000000-0000-0000-0003-000000000013",
                "00000000-0000-0000-0003-000000000014"
            ].map { $0.uppercased() })

            guard expectedUUIDStrings.count == 35 else {
                throw FixtureGenerationError.readBackFailed(
                    "Specification error: expectedUUIDStrings must contain exactly 35 unique UUIDs, got: \(expectedUUIDStrings.count)"
                )
            }

            var allActualUUIDs: [String] = []
            allActualUUIDs.append(contentsOf: try queryUUIDs(table: "ZPLATFORMCATEGORY").map { $0.uuidString.uppercased() })
            allActualUUIDs.append(contentsOf: try queryUUIDs(table: "ZACCOUNT").map { $0.uuidString.uppercased() })
            allActualUUIDs.append(contentsOf: try queryUUIDs(table: "ZACCOUNTDETAIL").map { $0.uuidString.uppercased() })
            allActualUUIDs.append(contentsOf: try queryUUIDs(table: "ZACTIVITYLOG").map { $0.uuidString.uppercased() })

            guard allActualUUIDs.count == 35 else {
                throw FixtureGenerationError.readBackFailed("Total UUID count mismatch: got \(allActualUUIDs.count), expected 35")
            }

            let actualUUIDSet = Set(allActualUUIDs)
            guard actualUUIDSet.count == 35 else {
                let duplicates = Dictionary(grouping: allActualUUIDs, by: { $0 })
                    .filter { $1.count > 1 }
                    .keys
                throw FixtureGenerationError.readBackFailed("Duplicate UUID detected! Distinct: \(actualUUIDSet.count)/35, duplicates: \(duplicates)")
            }

            guard actualUUIDSet == expectedUUIDStrings else {
                let extraUUIDs = actualUUIDSet.subtracting(expectedUUIDStrings)
                let missingUUIDs = expectedUUIDStrings.subtracting(actualUUIDSet)
                throw FixtureGenerationError.readBackFailed(
                    "UUID set mismatch (actualUUIDSet != expectedUUIDStrings). Extra UUIDs: \(extraUUIDs), Missing UUIDs: \(missingUUIDs)"
                )
            }

            // 4. Orphan Foreign Key Verification
            let orphanDetails = try queryInt("""
                SELECT count(*) FROM ZACCOUNTDETAIL
                WHERE ZACCOUNT IS NULL OR ZACCOUNT NOT IN (SELECT Z_PK FROM ZACCOUNT);
            """)
            guard orphanDetails == 0 else {
                throw FixtureGenerationError.readBackFailed("Orphan AccountDetail records detected: \(orphanDetails)")
            }

            let orphanLogs = try queryInt("""
                SELECT count(*) FROM ZACTIVITYLOG
                WHERE ZACCOUNT IS NULL OR ZACCOUNT NOT IN (SELECT Z_PK FROM ZACCOUNT);
            """)
            guard orphanLogs == 0 else {
                throw FixtureGenerationError.readBackFailed("Orphan ActivityLog records detected: \(orphanLogs)")
            }

            let orphanCategories = try queryInt("""
                SELECT count(*) FROM ZACCOUNT
                WHERE ZCATEGORY IS NOT NULL AND ZCATEGORY NOT IN (SELECT Z_PK FROM ZPLATFORMCATEGORY);
            """)
            guard orphanCategories == 0 else {
                throw FixtureGenerationError.readBackFailed("Orphan Category reference detected on ZACCOUNT: \(orphanCategories)")
            }
        }
    }
}
