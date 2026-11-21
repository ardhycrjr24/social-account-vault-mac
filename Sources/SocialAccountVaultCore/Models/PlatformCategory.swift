import Foundation
import SwiftData

/// Persistent platform category grouping accounts into functional domains.
///
/// Delete Behavior:
/// Deleting a category NULLIFIES its relationship on associated accounts.
/// Accounts are never cascade-deleted when a category is removed; they remain
/// preserved in the vault and can be reassigned to another category.
@Model
public final class PlatformCategory {
    @Attribute(.unique)
    public var id: UUID
    public var name: String
    public var iconName: String
    public var displayOrder: Int
    public var isDefault: Bool
    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Account.category)
    public var accounts: [Account] = []

    public init(
        id: UUID = UUID(),
        name: String,
        iconName: String,
        displayOrder: Int = 0,
        isDefault: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.displayOrder = displayOrder
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.accounts = []
    }

    /// Updates category metadata and sets updatedAt to current time.
    public func update(name: String, iconName: String, displayOrder: Int) {
        self.name = name
        self.iconName = iconName
        self.displayOrder = displayOrder
        self.updatedAt = Date()
    }
}
