import Foundation

/// Operating system of the primary device assigned to an account.
///
/// This is descriptive hardware/workstation context only. It stores no device
/// identifiers that could act as credentials, tokens, or session material.
public enum DeviceOSType: String, Identifiable, Hashable, CaseIterable, Sendable, Codable {
    case macOS = "macOS"
    case iOS = "iOS"
    case iPadOS = "iPadOS"
    case windows = "windows"
    case linux = "linux"
    case other = "other"

    public var id: String { rawValue }

    /// Safe default for legacy records and newly created accounts.
    public static let `default`: DeviceOSType = .macOS

    /// SF Symbol icon representing the device operating system.
    public var iconName: String {
        switch self {
        case .macOS:
            return "desktopcomputer"
        case .iOS:
            return "iphone"
        case .iPadOS:
            return "ipad"
        case .windows:
            return "pc"
        case .linux:
            return "terminal.fill"
        case .other:
            return "cpu"
        }
    }
}