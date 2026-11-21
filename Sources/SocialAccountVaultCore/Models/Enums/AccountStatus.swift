import Foundation

/// Operating status of a registered account.
public enum AccountStatus: String, Identifiable, Hashable, CaseIterable, Sendable, Codable {
    case active = "Active"
    case inactive = "Inactive"
    case pending = "Pending"
    case suspended = "Suspended"

    public var id: String { rawValue }

    /// SF Symbol icon associated with this status.
    public var iconName: String {
        switch self {
        case .active:
            return "checkmark.circle.fill"
        case .inactive:
            return "pause.circle.fill"
        case .pending:
            return "clock.fill"
        case .suspended:
            return "exclamationmark.triangle.fill"
        }
    }
}
