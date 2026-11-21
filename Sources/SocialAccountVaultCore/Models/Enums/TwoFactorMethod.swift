import Foundation

/// Two-factor authentication method configured for an account.
///
/// Security Invariant:
/// This enum records ONLY the method category. No authenticator seeds, OTP URIs,
/// hardware key secrets, or recovery codes are ever stored alongside it.
public enum TwoFactorMethod: String, Identifiable, Hashable, CaseIterable, Sendable, Codable {
    case authenticatorApp = "authenticatorApp"
    case hardwareKey = "hardwareKey"
    case smsBackup = "smsBackup"
    case passkey = "passkey"
    case none = "none"

    public var id: String { rawValue }

    /// Safe default for legacy records and newly created accounts.
    public static let `default`: TwoFactorMethod = .none

    /// SF Symbol icon representing the 2FA method.
    public var iconName: String {
        switch self {
        case .authenticatorApp:
            return "apps.iphone"
        case .hardwareKey:
            return "key.fill"
        case .smsBackup:
            return "message.fill"
        case .passkey:
            return "person.badge.key.fill"
        case .none:
            return "minus.circle"
        }
    }
}