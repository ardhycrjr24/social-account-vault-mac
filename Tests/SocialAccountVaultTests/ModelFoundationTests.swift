import Testing
import Foundation
import SwiftData
@testable import SocialAccountVaultCore

@Suite("SwiftData Model and Persistence Foundation Tests")
struct ModelFoundationTests {

    @Test("Verify SwiftData schema registers all 4 core entities")
    @MainActor
    func testSchemaEntities() {
        let schema = DatabaseConfiguration.schema
        #expect(schema.entities.count == 4)
    }

    @Test("Verify in-memory ModelContainer initialization")
    @MainActor
    func testModelContainerCreation() throws {
        let container = try DatabaseConfiguration.createModelContainer(inMemory: true)
        let context = ModelContext(container)
        #expect(context.container.schema.entities.count == 4)
        #expect(!context.hasChanges)
    }

    @Test("Verify Account entity instantiation and typed accessors")
    @MainActor
    func testAccountInstantiation() {
        let account = Account(
            name: "Main YouTube Channel",
            platform: PlatformType.youtube.rawValue,
            username: "techcreator",
            emailReference: "creator@example.com",
            profileURLString: "https://youtube.com/@techcreator",
            officialDashboardURLString: "https://studio.youtube.com",
            accountType: .creator,
            accountStatus: .active,
            monetizationStatus: .monetized,
            notes: "Verified primary channel"
        )

        #expect(account.name == "Main YouTube Channel")
        #expect(account.platform == "YouTube")
        #expect(account.username == "techcreator")
        #expect(account.accountType == .creator)
        #expect(account.accountStatus == .active)
        #expect(account.monetizationStatus == .monetized)
        #expect(account.isArchived == false)
        #expect(account.details.isEmpty)
        #expect(account.activityLogs.isEmpty)
    }

    @Test("Verify CategorySeeder creates exactly 8 categories idempotently")
    @MainActor
    func testCategorySeederIdempotency() throws {
        let container = try DatabaseConfiguration.createModelContainer(inMemory: true)
        let context = ModelContext(container)

        // Initial run
        _ = try CategorySeeder.seedDefaultCategoriesIfNeeded(modelContext: context)

        var descriptor = FetchDescriptor<PlatformCategory>()
        var categories = try context.fetch(descriptor)
        #expect(categories.count == 8)

        // Second run must be idempotent (no duplicates)
        _ = try CategorySeeder.seedDefaultCategoriesIfNeeded(modelContext: context)

        descriptor = FetchDescriptor<PlatformCategory>()
        categories = try context.fetch(descriptor)
        #expect(categories.count == 8)

        let names = Set(categories.map { $0.name })
        for platform in PlatformType.allCases {
            #expect(names.contains(platform.rawValue))
        }
    }

    @Test("Verify relationships: Category -> Account -> Details & ActivityLog")
    @MainActor
    func testModelRelationships() throws {
        let container = try DatabaseConfiguration.createModelContainer(inMemory: true)
        let context = ModelContext(container)

        let category = PlatformCategory(
            name: "Website & Domain",
            iconName: "globe",
            displayOrder: 8,
            isDefault: true
        )
        context.insert(category)

        let account = Account(
            name: "Personal Tech Blog",
            platform: "Website & Domain",
            username: "techblog.io",
            emailReference: "admin@techblog.io",
            category: category
        )
        context.insert(account)

        let detail = AccountDetail(
            key: "Cloudflare Zone ID",
            value: "cf_zone_123456",
            account: account
        )
        context.insert(detail)

        let log = ActivityLog(
            actionType: "Created",
            details: "Initial setup of techblog.io record",
            account: account
        )
        context.insert(log)

        try context.save()

        let accountDescriptor = FetchDescriptor<Account>()
        let fetchedAccounts = try context.fetch(accountDescriptor)
        #expect(fetchedAccounts.count == 1)

        guard let first = fetchedAccounts.first else {
            Issue.record("Expected to fetch 1 account")
            return
        }

        #expect(first.category?.name == "Website & Domain")
        #expect(first.details.count == 1)
        #expect(first.details.first?.key == "Cloudflare Zone ID")
        #expect(first.activityLogs.count == 1)
        #expect(first.activityLogs.first?.actionType == "Created")
    }
}
