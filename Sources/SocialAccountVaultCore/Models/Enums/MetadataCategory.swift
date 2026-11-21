import Foundation

/// Functional grouping for standardized `AccountDetail` metadata keys.
///
/// Derived from the four domain groups defined in the Phase 4 Database Design
/// (Section 4): Platform Identifiers, Infrastructure & DNS, Monetization Details,
/// and Device Context. Used to organize and validate typed metadata wrappers.
public enum MetadataCategory: String, CaseIterable, Identifiable, Hashable, Sendable, Codable {
    case platformIdentifier = "platform"
    case infrastructure = "infrastructure"
    case monetization = "monetization"
    case deviceContext = "device"

    public var id: String { rawValue }

    /// Human-readable display title for the category.
    public var displayName: String {
        switch self {
        case .platformIdentifier:
            return "Platform Identifiers"
        case .infrastructure:
            return "Infrastructure & DNS"
        case .monetization:
            return "Monetization Details"
        case .deviceContext:
            return "Device Context"
        }
    }

    /// All standardized keys belonging to this category.
    public var keys: [StandardMetadataKey] {
        StandardMetadataKey.allCases.filter { $0.category == self }
    }
}