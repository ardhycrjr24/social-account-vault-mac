import Testing
import Foundation
import SwiftData
@testable import SocialAccountVaultCore

@Suite("SQLite SwiftData Persistence and Lifecycle Tests")
struct PersistenceTests {

    private func makeTemporaryDatabaseURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        return tempDir.appendingPathComponent("vault_test_\(UUID().uuidString).sqlite")
    }

    private func cleanupDatabase(at url: URL) {
        let path = url.path
        try? FileManager.default.removeItem(atPath: path)
        try? FileManager.default.removeItem(atPath: "\(path)-shm")
        try? FileManager.default.removeItem(atPath: "\(path)-wal")
    }

    @Test("Verify full CRUD persistence cycle on SQLite store")
    @MainActor
    func testCRUDPersistence() throws {
        let dbURL = makeTemporaryDatabaseURL()
        defer { cleanupDatabase(at: dbURL) }

        let container = try DatabaseConfiguration.createModelContainer(at: dbURL, inMemory: false)
        let context = ModelContext(container)
        let service = VaultDataService(modelContext: context)

        // 1. Create
        let account = try service.createAccount(
            name: "Gaming Channel",
            platform: PlatformType.youtube.rawValue,
            username: "gamingpro",
            emailReference: "gaming@example.com",
            profileURLString: "https://youtube.com/@gamingpro",
            officialDashboardURLString: "https://studio.youtube.com",
            accountType: .creator,
            accountStatus: .active,
            monetizationStatus: .monetized,
            notes: "Main stream account"
        )
        let accountID = account.id

        // Verify insertion
        var active = try service.fetchActiveAccounts()
        #expect(active.count == 1)
        #expect(active.first?.id == accountID)
        #expect(active.first?.name == "Gaming Channel")

        // 2. Add Detail
        try service.addDetail(to: account, key: "Channel ID", value: "UC_123456789")
        #expect(account.details.count == 1)
        #expect(account.details.first?.key == "Channel ID")

        // 3. Update
        try service.updateAccount(
            account,
            name: "Gaming Channel Pro",
            username: "gamingpro_official",
            emailReference: "gaming_new@example.com",
            profileURLString: "https://youtube.com/@gamingpro_official",
            officialDashboardURLString: "https://studio.youtube.com",
            accountType: .creator,
            accountStatus: .active,
            monetizationStatus: .monetized,
            notes: "Updated sponsorship notes"
        )

        active = try service.fetchActiveAccounts()
        #expect(active.first?.name == "Gaming Channel Pro")
        #expect(active.first?.username == "gamingpro_official")

        // 4. Delete & Cascade Check
        try service.deleteAccount(account)
        active = try service.fetchActiveAccounts()
        #expect(active.isEmpty)

        // Verify orphaned details were cascade-deleted
        let detailDescriptor = FetchDescriptor<AccountDetail>()
        let remainingDetails = try context.fetch(detailDescriptor)
        #expect(remainingDetails.isEmpty)
    }

    @Test("Verify data survives across database closing and reopening (restart simulation)")
    @MainActor
    func testDatabaseReopeningAndPersistenceAcrossRestart() throws {
        let dbURL = makeTemporaryDatabaseURL()
        defer { cleanupDatabase(at: dbURL) }

        let accountUUID = UUID()

        // --- SESSION 1: Application Boot & Data Creation ---
        do {
            let container1 = try DatabaseConfiguration.createModelContainer(at: dbURL, inMemory: false)
            let context1 = ModelContext(container1)
            let service1 = VaultDataService(modelContext: context1)

            let account = try service1.createAccount(
                name: "Primary TikTok",
                platform: PlatformType.tiktok.rawValue,
                username: "creative_daily",
                emailReference: "contact@daily.com",
                profileURLString: "https://tiktok.com/@creative_daily",
                officialDashboardURLString: "https://tiktok.com",
                accountType: .creator,
                accountStatus: .active,
                monetizationStatus: .eligible,
                notes: "Reaches 500k followers"
            )
            account.id = accountUUID

            try service1.addDetail(to: account, key: "Creator Marketplace ID", value: "TT_CMP_998877")
            try context1.save()
        }

        // --- SESSION 2: Application Restart & Data Re-fetch from Disk ---
        do {
            let container2 = try DatabaseConfiguration.createModelContainer(at: dbURL, inMemory: false)
            let context2 = ModelContext(container2)
            let service2 = VaultDataService(modelContext: context2)

            let accounts = try service2.fetchActiveAccounts()
            #expect(accounts.count == 1)

            guard let restored = accounts.first else {
                Issue.record("Expected 1 restored account after reopening SQLite store")
                return
            }

            #expect(restored.id == accountUUID)
            #expect(restored.name == "Primary TikTok")
            #expect(restored.username == "creative_daily")
            #expect(restored.platform == "TikTok")
            #expect(restored.monetizationStatus == .eligible)
            #expect(restored.details.count == 1)
            #expect(restored.details.first?.key == "Creator Marketplace ID")
            #expect(restored.details.first?.value == "TT_CMP_998877")
            #expect(restored.activityLogs.count >= 2)
        }
    }

    @Test("Verify account archival and restoration lifecycle")
    @MainActor
    func testAccountArchivalAndRestoration() throws {
        let container = try DatabaseConfiguration.createModelContainer(inMemory: true)
        let context = ModelContext(container)
        let service = VaultDataService(modelContext: context)

        let account = try service.createAccount(
            name: "Old Campaign Account",
            platform: PlatformType.facebook.rawValue,
            username: "old_camp"
        )

        var active = try service.fetchActiveAccounts()
        var archived = try service.fetchArchivedAccounts()
        #expect(active.count == 1)
        #expect(archived.isEmpty)

        // Archive
        try service.archiveAccount(account)
        active = try service.fetchActiveAccounts()
        archived = try service.fetchArchivedAccounts()
        #expect(active.isEmpty)
        #expect(archived.count == 1)
        #expect(archived.first?.name == "Old Campaign Account")

        // Restore
        try service.restoreAccount(account)
        active = try service.fetchActiveAccounts()
        archived = try service.fetchArchivedAccounts()
        #expect(active.count == 1)
        #expect(archived.isEmpty)
    }

    @Test("Verify category reassignment preserves account data and logs transition")
    @MainActor
    func testCategoryReassignment() throws {
        let container = try DatabaseConfiguration.createModelContainer(inMemory: true)
        let context = ModelContext(container)
        let service = VaultDataService(modelContext: context)

        let catYouTube = PlatformCategory(name: "YouTube", iconName: "play.rectangle.fill", displayOrder: 1)
        let catInstagram = PlatformCategory(name: "Instagram", iconName: "camera.fill", displayOrder: 2)
        context.insert(catYouTube)
        context.insert(catInstagram)

        let account = try service.createAccount(
            name: "Cross-Platform Handle",
            platform: "YouTube",
            username: "crosshandle",
            category: catYouTube
        )

        try service.addDetail(to: account, key: "Subscriber Count", value: "100000")

        #expect(account.category?.name == "YouTube")
        #expect(account.platform == "YouTube")
        #expect(account.details.count == 1)

        // Reassign category to Instagram
        try service.reassignCategory(account: account, to: catInstagram)

        #expect(account.category?.name == "Instagram")
        #expect(account.platform == "Instagram")
        #expect(account.details.count == 1)
        #expect(account.details.first?.value == "100000")

        // Deterministic event ordering via sorted relationship
        let logs = account.sortedActivityLogs
        #expect(logs.count == 3)
        #expect(logs[0].actionType == "Created")
        #expect(logs[1].actionType == "Detail Added")
        #expect(logs[2].actionType == "Category Reassigned")
        #expect(logs.last?.actionType == "Category Reassigned")

        // Deterministic event ordering via service fetch query
        let fetchedLogs = try service.fetchActivityLogs(for: account)
        #expect(fetchedLogs.count == 3)
        #expect(fetchedLogs.last?.actionType == "Category Reassigned")
    }

    @Test("Verify deleting category nullifies relationship without deleting account")
    @MainActor
    func testCategoryDeletionPreservesAccounts() throws {
        let container = try DatabaseConfiguration.createModelContainer(inMemory: true)
        let context = ModelContext(container)
        let service = VaultDataService(modelContext: context)

        let customCat = PlatformCategory(name: "Legacy Forum", iconName: "bubble.left.fill", displayOrder: 9)
        context.insert(customCat)

        let account = try service.createAccount(
            name: "Forum Admin",
            platform: "Legacy Forum",
            username: "admin_user",
            category: customCat
        )

        try context.save()
        #expect(account.category?.name == "Legacy Forum")

        // Delete the category
        context.delete(customCat)
        try context.save()

        // Account must STILL exist, with category reference nullified
        let accounts = try service.fetchActiveAccounts()
        #expect(accounts.count == 1)
        #expect(accounts.first?.name == "Forum Admin")
        #expect(accounts.first?.category == nil)
    }

    @Test("Verify Add Account success, field population, and audit log generation")
    @MainActor
    func testAddAccountSuccessAndAuditLogging() throws {
        let dbURL = makeTemporaryDatabaseURL()
        defer { cleanupDatabase(at: dbURL) }

        let container = try DatabaseConfiguration.createModelContainer(at: dbURL, inMemory: false)
        let context = ModelContext(container)
        let service = VaultDataService(modelContext: context)

        // Seed default categories
        _ = try CategorySeeder.seedDefaultCategoriesIfNeeded(modelContext: context)

        let account = try service.createAccount(
            name: "Alpha Tech Vlog",
            platform: PlatformType.youtube.rawValue,
            username: "alphavlog",
            emailReference: "partner@alphavlog.tv",
            profileURLString: "https://youtube.com/@alphavlog",
            officialDashboardURLString: "https://studio.youtube.com",
            accountType: .creator,
            accountStatus: .active,
            monetizationStatus: .monetized,
            notes: "Verified partner channel with AdSense link"
        )

        // Verify entity properties
        #expect(account.name == "Alpha Tech Vlog")
        #expect(account.platform == "YouTube")
        #expect(account.username == "alphavlog")
        #expect(account.emailReference == "partner@alphavlog.tv")
        #expect(account.profileURLString == "https://youtube.com/@alphavlog")
        #expect(account.officialDashboardURLString == "https://studio.youtube.com")
        #expect(account.accountType == .creator)
        #expect(account.accountStatus == .active)
        #expect(account.monetizationStatus == .monetized)
        #expect(account.notes == "Verified partner channel with AdSense link")
        #expect(!account.isArchived)
        #expect(account.category?.name == "YouTube")

        // Verify database query
        let fetchedAccounts = try service.fetchActiveAccounts()
        #expect(fetchedAccounts.count == 1)
        #expect(fetchedAccounts.first?.id == account.id)

        // Verify audit log
        let logs = account.sortedActivityLogs
        #expect(logs.count == 1)
        #expect(logs.first?.actionType == "Created")
        #expect(logs.first?.details.contains("YouTube") == true)
        #expect(logs.first?.sequenceNumber == 1)
    }

    @Test("Verify Add Account input validation and credential rejection")
    @MainActor
    func testAddAccountInputValidation() throws {
        let container = try DatabaseConfiguration.createModelContainer(inMemory: true)
        let context = ModelContext(container)
        let service = VaultDataService(modelContext: context)

        // 1. Blank name rejection
        #expect(throws: VaultError.self) {
            try service.createAccount(name: "   ", platform: "YouTube")
        }

        // 2. Oversized name (>100 characters)
        let longName = String(repeating: "A", count: 101)
        #expect(throws: VaultError.self) {
            try service.createAccount(name: longName, platform: "YouTube")
        }

        // 3. Oversized username (>100 characters)
        let longUsername = String(repeating: "u", count: 101)
        #expect(throws: VaultError.self) {
            try service.createAccount(name: "Valid Name", platform: "YouTube", username: longUsername)
        }

        // 4. Invalid profile URL scheme
        #expect(throws: VaultError.self) {
            try service.createAccount(
                name: "Valid Name",
                platform: "YouTube",
                profileURLString: "ftp://example.com/profile"
            )
        }

        // 5. Invalid dashboard URL scheme
        #expect(throws: VaultError.self) {
            try service.createAccount(
                name: "Valid Name",
                platform: "YouTube",
                officialDashboardURLString: "not-a-valid-url"
            )
        }

        // 6. Security Invariant: Credential keyword in username
        #expect(throws: VaultError.self) {
            try service.createAccount(
                name: "Hacker Channel",
                platform: "YouTube",
                username: "admin_password_123"
            )
        }

        // 7. Security Invariant: Credential keyword in notes
        #expect(throws: VaultError.self) {
            try service.createAccount(
                name: "Secret Channel",
                platform: "YouTube",
                notes: "OAuth access_token = secret123"
            )
        }
    }

    @Test("Verify newly added account survives container closure and reopening")
    @MainActor
    func testAddedAccountPersistenceAcrossReopen() throws {
        let dbURL = makeTemporaryDatabaseURL()
        defer { cleanupDatabase(at: dbURL) }

        var accountID: UUID = UUID()

        // Session 1: Create and save
        do {
            let container1 = try DatabaseConfiguration.createModelContainer(at: dbURL, inMemory: false)
            let context1 = ModelContext(container1)
            let service1 = VaultDataService(modelContext: context1)

            let cat = PlatformCategory(name: "TikTok", iconName: "music.note", displayOrder: 3)
            context1.insert(cat)

            let account = try service1.createAccount(
                name: "Viral Clips Studio",
                platform: "TikTok",
                username: "viralclips",
                emailReference: "clips@viral.com",
                profileURLString: "https://www.tiktok.com/@viralclips",
                officialDashboardURLString: "https://www.tiktok.com",
                accountType: .brand,
                accountStatus: .active,
                monetizationStatus: .eligible,
                category: cat
            )
            accountID = account.id
            try context1.save()
        }

        // Session 2: Reopen container and assert persistence
        do {
            let container2 = try DatabaseConfiguration.createModelContainer(at: dbURL, inMemory: false)
            let context2 = ModelContext(container2)
            let service2 = VaultDataService(modelContext: context2)

            let accounts = try service2.fetchActiveAccounts()
            #expect(accounts.count == 1)
            let loaded = accounts.first
            #expect(loaded?.id == accountID)
            #expect(loaded?.name == "Viral Clips Studio")
            #expect(loaded?.platform == "TikTok")
            #expect(loaded?.username == "viralclips")
            #expect(loaded?.category?.name == "TikTok")
            #expect(loaded?.sortedActivityLogs.count == 1)
            #expect(loaded?.sortedActivityLogs.first?.actionType == "Created")
        }
    }

    @Test("Verify updating existing account in-place preserves metadata and notes without duplication")
    @MainActor
    func testUpdateAccountInPlaceWithoutDuplication() throws {
        let container = try DatabaseConfiguration.createModelContainer(inMemory: true)
        let context = ModelContext(container)
        let service = VaultDataService(modelContext: context)

        let account = try service.createAccount(
            name: "Brand Channel",
            platform: "YouTube",
            username: "brand_yt",
            notes: "Original channel notes"
        )
        let originalID = account.id

        // Add metadata
        try service.addDetail(to: account, key: "Channel ID", value: "UC_987654321")
        #expect(account.details.count == 1)

        // Perform Update
        try service.updateAccount(
            account,
            name: "Brand Channel Official",
            username: "brand_yt_verified",
            emailReference: "brand@example.com",
            profileURLString: "https://youtube.com/@brand_yt_verified",
            officialDashboardURLString: "https://studio.youtube.com",
            accountType: .brand,
            accountStatus: .active,
            monetizationStatus: .monetized,
            notes: "Updated sponsorship and network notes"
        )

        // Assert NO duplicate account was created
        let allActive = try service.fetchActiveAccounts()
        #expect(allActive.count == 1)
        #expect(allActive.first?.id == originalID)
        #expect(allActive.first?.name == "Brand Channel Official")
        #expect(allActive.first?.username == "brand_yt_verified")
        #expect(allActive.first?.notes == "Updated sponsorship and network notes")

        // Assert metadata was preserved intact
        #expect(allActive.first?.details.count == 1)
        #expect(allActive.first?.details.first?.key == "Channel ID")
        #expect(allActive.first?.details.first?.value == "UC_987654321")

        // Assert audit log records "Updated"
        let logs = account.sortedActivityLogs
        #expect(logs.count == 3) // Created, Detail Added, Updated
        #expect(logs.last?.actionType == "Updated")
        #expect(logs.last?.sequenceNumber == 3)
    }

    @Test("Verify Archive and Restore lifecycle preserves data and records audit logs")
    @MainActor
    func testArchiveAndRestoreFlow() throws {
        let container = try DatabaseConfiguration.createModelContainer(inMemory: true)
        let context = ModelContext(container)
        let service = VaultDataService(modelContext: context)

        let account = try service.createAccount(
            name: "Archived Project",
            platform: "Instagram",
            username: "archived_ig"
        )

        // Initial State
        var active = try service.fetchActiveAccounts()
        var archived = try service.fetchArchivedAccounts()
        #expect(active.count == 1)
        #expect(archived.count == 0)

        // 1. Archive
        try service.archiveAccount(account)
        active = try service.fetchActiveAccounts()
        archived = try service.fetchArchivedAccounts()
        #expect(active.count == 0)
        #expect(archived.count == 1)
        #expect(archived.first?.name == "Archived Project")
        #expect(account.sortedActivityLogs.last?.actionType == "Archived")

        // 2. Restore
        try service.restoreAccount(account)
        active = try service.fetchActiveAccounts()
        archived = try service.fetchArchivedAccounts()
        #expect(active.count == 1)
        #expect(archived.count == 0)
        #expect(active.first?.name == "Archived Project")
        #expect(account.sortedActivityLogs.last?.actionType == "Restored")
    }

    @Test("Verify permanent deletion cascade and data scrubbing policy")
    @MainActor
    func testPermanentDeleteCascadeAndScrubbingPolicy() throws {
        let container = try DatabaseConfiguration.createModelContainer(inMemory: true)
        let context = ModelContext(container)
        let service = VaultDataService(modelContext: context)

        let account = try service.createAccount(
            name: "Temporary Profile",
            platform: "Facebook",
            username: "temp_fb"
        )
        try service.addDetail(to: account, key: "Page ID", value: "PAGE_112233")
        #expect(account.details.count == 1)
        #expect(account.activityLogs.count == 2) // Created, Detail Added

        // Perform Permanent Delete
        try service.deleteAccount(account)

        // Verify account is removed
        let active = try service.fetchActiveAccounts()
        let archived = try service.fetchArchivedAccounts()
        #expect(active.isEmpty)
        #expect(archived.isEmpty)

        // Verify cascading delete removed details (privacy-first scrubbing)
        let detailDescriptor = FetchDescriptor<AccountDetail>()
        let remainingDetails = try context.fetch(detailDescriptor)
        #expect(remainingDetails.isEmpty)

        // Verify cascading delete removed related logs (scrubbing policy)
        let logDescriptor = FetchDescriptor<ActivityLog>()
        let remainingLogs = try context.fetch(logDescriptor)
        #expect(remainingLogs.isEmpty)
    }

    @Test("Verify AddAccountView edit mode prefill integrity and mode properties")
    @MainActor
    func testEditPrefillIntegrityAndFormMode() throws {
        let account = Account(
            name: "Prefill Test Channel",
            platform: "YouTube",
            username: "prefill_user",
            emailReference: "prefill@example.com",
            profileURLString: "https://youtube.com/@prefill_user",
            officialDashboardURLString: "https://studio.youtube.com",
            accountType: .creator,
            accountStatus: .active,
            monetizationStatus: .monetized,
            notes: "Important creator notes"
        )

        // Verify Create Mode View
        let createView = AddAccountView(initialPlatform: .tiktok)
        #expect(createView.isEditMode == false)
        #expect(createView.navigationTitleString == "New Account")
        #expect(createView.saveButtonString == "Save")

        // Verify Edit Mode View
        let editView = AddAccountView(editing: account)
        #expect(editView.isEditMode == true)
        #expect(editView.accountToEdit?.id == account.id)
        #expect(editView.navigationTitleString == "Edit Account")
        #expect(editView.saveButtonString == "Save Changes")
    }

    @Test("Verify AccountDetailView status check records audit event")
    @MainActor
    func testAccountDetailViewStatusCheck() throws {
        let account = Account(
            name: "Audit Check Channel",
            platform: "YouTube",
            username: "audit_checker"
        )
        account.appendActivityLog(actionType: "Created", details: "Initial creation")

        #expect(account.sortedActivityLogs.count == 1)

        // Mark Checked
        account.markChecked()

        #expect(account.sortedActivityLogs.count == 2)
        #expect(account.sortedActivityLogs.last?.actionType == "Status Checked")
        #expect(account.sortedActivityLogs.last?.sequenceNumber == 2)
    }

    @Test("Verify single update produces exactly one audit event and repeated updates do not duplicate")
    @MainActor
    func testUpdateAccountAuditDeduplicationAndIdempotency() throws {
        let container = try DatabaseConfiguration.createModelContainer(inMemory: true)
        let context = ModelContext(container)
        let service = VaultDataService(modelContext: context)

        let account = try service.createAccount(
            name: "Clumsy Cats Demo",
            platform: "YouTube",
            username: "clumsycats",
            notes: "Demo notes"
        )
        let originalID = account.id

        // Initial State: Only 1 Created log
        #expect(account.sortedActivityLogs.count == 1)
        #expect(account.sortedActivityLogs.first?.actionType == "Created")
        #expect(account.sortedActivityLogs.first?.sequenceNumber == 1)

        // 1. Single update with actual change (username change)
        let didUpdate1 = try service.updateAccount(
            account,
            name: "Clumsy Cats Demo",
            username: "clumsycats_test",
            emailReference: "",
            profileURLString: "",
            officialDashboardURLString: "",
            accountType: .personal,
            accountStatus: .active,
            monetizationStatus: .notMonetized,
            notes: "Demo notes"
        )

        #expect(didUpdate1 == true)
        #expect(account.id == originalID)
        #expect(account.username == "clumsycats_test")
        // Exactly one Updated event added (#2)
        #expect(account.sortedActivityLogs.count == 2)
        #expect(account.sortedActivityLogs.last?.actionType == "Updated")
        #expect(account.sortedActivityLogs.last?.sequenceNumber == 2)

        // 2. Update without change: must NOT produce an audit event
        let didUpdate2 = try service.updateAccount(
            account,
            name: "Clumsy Cats Demo",
            username: "clumsycats_test",
            emailReference: "",
            profileURLString: "",
            officialDashboardURLString: "",
            accountType: .personal,
            accountStatus: .active,
            monetizationStatus: .notMonetized,
            notes: "Demo notes"
        )

        #expect(didUpdate2 == false)
        #expect(account.id == originalID)
        #expect(account.sortedActivityLogs.count == 2) // Remains 2, no event #3

        // 3. Repeated invocations with identical values (simulating duplicate triggers / fast clicks)
        for _ in 0..<5 {
            let res = try service.updateAccount(
                account,
                name: "Clumsy Cats Demo",
                username: "clumsycats_test",
                emailReference: "",
                profileURLString: "",
                officialDashboardURLString: "",
                accountType: .personal,
                accountStatus: .active,
                monetizationStatus: .notMonetized,
                notes: "Demo notes"
            )
            #expect(res == false)
        }

        #expect(account.id == originalID)
        #expect(account.sortedActivityLogs.count == 2) // Still strictly 2 logs

        // 4. Another genuine modification (notes change) produces exactly one new event (#3)
        let didUpdate3 = try service.updateAccount(
            account,
            name: "Clumsy Cats Demo",
            username: "clumsycats_test",
            emailReference: "",
            profileURLString: "",
            officialDashboardURLString: "",
            accountType: .personal,
            accountStatus: .active,
            monetizationStatus: .notMonetized,
            notes: "Updated channel notes for Clumsy Cats"
        )

        #expect(didUpdate3 == true)
        #expect(account.id == originalID)
        #expect(account.notes == "Updated channel notes for Clumsy Cats")
        #expect(account.sortedActivityLogs.count == 3)
        #expect(account.sortedActivityLogs.last?.actionType == "Updated")
        #expect(account.sortedActivityLogs.last?.sequenceNumber == 3)
    }

    @Test("Verify updated account data and deduplicated audit logs survive SQLite database reopen")
    @MainActor
    func testUpdatedAccountPersistenceAcrossReopen() throws {
        let dbURL = makeTemporaryDatabaseURL()
        defer { cleanupDatabase(at: dbURL) }

        let accountUUID = UUID()

        // --- SESSION 1: Create, Update, and Idempotency Check on Disk ---
        do {
            let container1 = try DatabaseConfiguration.createModelContainer(at: dbURL, inMemory: false)
            let context1 = ModelContext(container1)
            let service1 = VaultDataService(modelContext: context1)

            let account = try service1.createAccount(
                name: "Clumsy Cats Demo",
                platform: "YouTube",
                username: "clumsycats",
                notes: "Initial notes"
            )
            account.id = accountUUID

            // Genuine update
            let updated = try service1.updateAccount(
                account,
                name: "Clumsy Cats Demo",
                username: "clumsycats_test",
                emailReference: "cats@example.com",
                profileURLString: "https://youtube.com/@clumsycats_test",
                officialDashboardURLString: "https://studio.youtube.com",
                accountType: .creator,
                accountStatus: .active,
                monetizationStatus: .monetized,
                notes: "Verified cat channel"
            )
            #expect(updated == true)

            // Attempt duplicate update
            let dup = try service1.updateAccount(
                account,
                name: "Clumsy Cats Demo",
                username: "clumsycats_test",
                emailReference: "cats@example.com",
                profileURLString: "https://youtube.com/@clumsycats_test",
                officialDashboardURLString: "https://studio.youtube.com",
                accountType: .creator,
                accountStatus: .active,
                monetizationStatus: .monetized,
                notes: "Verified cat channel"
            )
            #expect(dup == false)

            #expect(account.sortedActivityLogs.count == 2)
            try context1.save()
        }

        // --- SESSION 2: Reopen SQLite store and verify persistence & audit logs ---
        do {
            let container2 = try DatabaseConfiguration.createModelContainer(at: dbURL, inMemory: false)
            let context2 = ModelContext(container2)
            let service2 = VaultDataService(modelContext: context2)

            let accounts = try service2.fetchActiveAccounts()
            #expect(accounts.count == 1)

            guard let restored = accounts.first else {
                Issue.record("Expected 1 restored account after reopening SQLite store")
                return
            }

            #expect(restored.id == accountUUID)
            #expect(restored.name == "Clumsy Cats Demo")
            #expect(restored.username == "clumsycats_test")
            #expect(restored.emailReference == "cats@example.com")
            #expect(restored.profileURLString == "https://youtube.com/@clumsycats_test")
            #expect(restored.officialDashboardURLString == "https://studio.youtube.com")
            #expect(restored.accountType == .creator)
            #expect(restored.monetizationStatus == .monetized)
            #expect(restored.notes == "Verified cat channel")

            // Verify audit logs survived with exact sequence #1 Created, #2 Updated
            let logs = restored.sortedActivityLogs
            #expect(logs.count == 2)
            #expect(logs[0].actionType == "Created")
            #expect(logs[0].sequenceNumber == 1)
            #expect(logs[1].actionType == "Updated")
            #expect(logs[1].sequenceNumber == 2)
        }
    }
}
