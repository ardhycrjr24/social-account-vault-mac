import Foundation

/// Monetization qualification and revenue status for an account.
public enum MonetizationStatus: String, Identifiable, Hashable, CaseIterable, Sendable, Codable {
    case notMonetized = "Not Monetized"
    case applied = "Applied"
    case eligible = "Eligible"
    case monetized = "Monetized"
    case rejected = "Rejected"
    case notApplicable = "Not Applicable"

    public var id: String { rawValue }

    /// SF Symbol icon for monetization indicator.
    public var iconName: String {
        switch self {
        case .monetized:
            return "dollarsign.circle.fill"
        case .eligible:
            return "star.circle.fill"
        case .applied:
            return "hourglass.circle.fill"
        case .rejected:
            return "xmark.circle.fill"
        case .notMonetized:
            return "circle"
        case .notApplicable:
            return "minus.circle"
        }
    }
}
