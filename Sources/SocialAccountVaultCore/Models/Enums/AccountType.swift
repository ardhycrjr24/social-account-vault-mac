import Foundation

/// Functional category of the account (e.g. personal, business, creator).
public enum AccountType: String, Identifiable, Hashable, CaseIterable, Sendable, Codable {
    case personal = "Personal"
    case business = "Business"
    case creator = "Creator"
    case brand = "Brand"
    case affiliate = "Affiliate"
    case administrative = "Administrative"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .personal:
            return "person.fill"
        case .business:
            return "briefcase.fill"
        case .creator:
            return "sparkles"
        case .brand:
            return "tag.fill"
        case .affiliate:
            return "cart.fill"
        case .administrative:
            return "wrench.and.screwdriver.fill"
        }
    }
}
