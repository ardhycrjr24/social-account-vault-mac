import Foundation
import SwiftData

/// Idempotent service to initialize and maintain the 8 default platform categories.
@MainActor
public final class CategorySeeder: Sendable {
    /// Seeds default platform categories into the database if they do not exist.
    ///
    /// Idempotency guarantee:
    /// - Checks existing category names before inserting.
    /// - Never deletes existing categories or decouples user accounts.
    /// - Updates iconName and displayOrder for defaults to keep them consistent.
    /// - Safe to call repeatedly during application launch or migrations.
    @discardableResult
    public static func seedDefaultCategoriesIfNeeded(modelContext: ModelContext) throws -> [PlatformCategory] {
        let descriptor = FetchDescriptor<PlatformCategory>(sortBy: [SortDescriptor(\.displayOrder)])
        let existingCategories = try modelContext.fetch(descriptor)
        let categoryMap = Dictionary(uniqueKeysWithValues: existingCategories.map { ($0.name, $0) })

        for platform in PlatformType.allCases {
            if let existing = categoryMap[platform.rawValue] {
                // Keep default metadata consistent without touching accounts
                if existing.iconName != platform.iconName || existing.displayOrder != platform.defaultOrder {
                    existing.iconName = platform.iconName
                    existing.displayOrder = platform.defaultOrder
                    existing.updatedAt = Date()
                }
            } else {
                let newCategory = PlatformCategory(
                    name: platform.rawValue,
                    iconName: platform.iconName,
                    displayOrder: platform.defaultOrder,
                    isDefault: true
                )
                modelContext.insert(newCategory)
            }
        }

        try modelContext.save()
        return try modelContext.fetch(descriptor)
    }
}
