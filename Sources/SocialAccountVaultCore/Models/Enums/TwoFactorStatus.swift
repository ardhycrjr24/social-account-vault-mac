import Foundation

/// Two-factor authentication status for an account.
///
/// Security Invariant:
/// This enum tracks ONLY the operational status of 2FA. It must never carry
/// authenticator seeds, OTP secrets, recovery codes, or any credential material.
public enum TwoFactorStatus: String, Identifiable, Hashable, CaseIterable, Sendable, Codable {
    case enabled = "enabled"
    case disabled = "disabled"
    case enforcedByOrg = "enforcedByOrg"
    case unknown = "unknown"

    public var id: String { rawValue }

    /// Safe default for legacy records and newly created accounts.
    public static let `default`: TwoFactorStatus = .unknown

    /// SF Symbol icon representing the 2FA status.
    public var iconName: String {
        switch self {
        case .enabled:
            return "lock.shield.fill"
        case .disabled:
            return "lock.open.fill"
        case .enforcedByOrg:
            return "building.2.crop.circle.fill"
        case .unknown:
            return "questionmark.circle.fill"
        }
    }
}

/// Aturan kombinasi status/metode 2FA yang disetujui produk (V1).
/// Murni & Sendable — dipakai service dan UI tanpa isolasi actor.
public extension TwoFactorStatus {
    func allows(method: TwoFactorMethod) -> Bool {
        switch self {
        case .enabled:
            return method != .none
        case .disabled, .unknown:
            return method == .none
        case .enforcedByOrg:
            return true
        }
    }
}