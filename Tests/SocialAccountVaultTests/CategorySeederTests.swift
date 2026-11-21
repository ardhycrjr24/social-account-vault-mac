import Testing
import Foundation
import SwiftData
@testable import SocialAccountVaultCore

@Suite("Category Seeder Idempotency and Integrity Tests")
struct CategorySeederTests {

    @Test("Verify seeder creates all 8 core platform categories")
    @MainActor
    func testSeedingDefaultCategories() throws {
        let container = try DatabaseConfiguration.createModelContainer(inMemory: true)
        let context = ModelContext(container)

        let seeded = try CategorySeeder.seedDefaultCategoriesIfNeeded(modelContext: context)
        #expect(seeded.count == 8)

        let names = Set(seeded.map { $0.name })
        for platform in PlatformType.allCases {
            #expect(names.contains(platform.rawValue))
        }
    }

    @Test("Verify seeder is strictly idempotent across multiple repeated invocations")
    @MainActor
    func testSeederRepeatedInvocations() throws {
        let container = try DatabaseConfiguration.createModelContainer(inMemory: true)
        let context = ModelContext(container)

        // Invoke seeder 5 times sequentially
        for _ in 1...5 {
            _ = try CategorySeeder.seedDefaultCategoriesIfNeeded(modelContext: context)
        }

        let descriptor = FetchDescriptor<PlatformCategory>()
        let totalCategories = try context.fetch(descriptor)
        #expect(totalCategories.count == 8)
    }

    @Test("Verify seeder preserves user-created custom categories")
    @MainActor
    func testSeederPreservesCustomCategories() throws {
        let container = try DatabaseConfiguration.createModelContainer(inMemory: true)
        let context = ModelContext(container)

        // Insert custom category before seeding
        let custom = PlatformCategory(
            name: "Substack Newsletter",
            iconName: "newspaper.fill",
            displayOrder: 99,
            isDefault: false
        )
        context.insert(custom)
        try context.save()

        // Run seeder
        _ = try CategorySeeder.seedDefaultCategoriesIfNeeded(modelContext: context)

        let descriptor = FetchDescriptor<PlatformCategory>()
        let all = try context.fetch(descriptor)
        #expect(all.count == 9)

        let names = Set(all.map { $0.name })
        #expect(names.contains("Substack Newsletter"))
        for platform in PlatformType.allCases {
            #expect(names.contains(platform.rawValue))
        }
    }

    @Test("Verify seeder does not sever existing account relationships")
    @MainActor
    func testSeederPreservesAccountRelationships() throws {
        let container = try DatabaseConfiguration.createModelContainer(inMemory: true)
        let context = ModelContext(container)
        let service = VaultDataService(modelContext: context)

        // Initial seed
        let seeded = try CategorySeeder.seedDefaultCategoriesIfNeeded(modelContext: context)
        guard let ytCategory = seeded.first(where: { $0.name == PlatformType.youtube.rawValue }) else {
            Issue.record("Expected YouTube category to exist")
            return
        }

        // Create account tied to YouTube
        let account = try service.createAccount(
            name: "Main Channel",
            platform: PlatformType.youtube.rawValue,
            username: "main_channel",
            category: ytCategory
        )
        #expect(account.category?.name == "YouTube")

        // Run seeder again
        _ = try CategorySeeder.seedDefaultCategoriesIfNeeded(modelContext: context)

        // Verify account still points to the YouTube category
        let accounts = try service.fetchActiveAccounts()
        #expect(accounts.count == 1)
        #expect(accounts.first?.category?.name == "YouTube")
    }
}
