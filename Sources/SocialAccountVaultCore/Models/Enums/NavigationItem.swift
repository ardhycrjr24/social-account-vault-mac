import Foundation

/// Navigation destinations supported in the Social Account Vault sidebar.
public enum NavigationItem: String, Identifiable, Hashable, CaseIterable, Sendable {
    case dashboard = "Dashboard"
    case allAccounts = "All Accounts"
    case youtube = "YouTube"
    case instagram = "Instagram"
    case tiktok = "TikTok"
    case facebook = "Facebook"
    case email = "Email"
    case affiliateMonetization = "Affiliate & Monetization"
    case websiteDomain = "Website & Domain"
    case archive = "Archive"
    case settings = "Settings"

    public var id: String { rawValue }

    /// SF Symbol icon name representing this navigation destination.
    public var iconName: String {
        switch self {
        case .dashboard:
            return "gauge.with.needle"
        case .allAccounts:
            return "person.2.fill"
        case .youtube:
            return "play.rectangle.fill"
        case .instagram:
            return "camera.fill"
        case .tiktok:
            return "music.note"
        case .facebook:
            return "bubble.left.and.bubble.right.fill"
        case .email:
            return "envelope.fill"
        case .affiliateMonetization:
            return "chart.line.uptrend.xyaxis"
        case .websiteDomain:
            return "globe"
        case .archive:
            return "archivebox.fill"
        case .settings:
            return "gearshape.fill"
        }
    }

    /// Logical sidebar section group.
    public var sectionGroup: NavigationSection {
        switch self {
        case .dashboard, .allAccounts:
            return .overview
        case .youtube, .instagram, .tiktok, .facebook, .email, .affiliateMonetization, .websiteDomain:
            return .platforms
        case .archive, .settings:
            return .system
        }
    }

    /// Associated platform type filter, if any.
    public var targetPlatformTypes: [PlatformType] {
        switch self {
        case .youtube:
            return [.youtube]
        case .instagram:
            return [.instagram]
        case .tiktok:
            return [.tiktok]
        case .facebook:
            return [.facebook]
        case .email:
            return [.email]
        case .affiliateMonetization:
            return [.shopeeAffiliate, .googleAdSense]
        case .websiteDomain:
            return [.websiteDomain]
        case .dashboard, .allAccounts, .archive, .settings:
            return []
        }
    }
}

/// Logical grouping for sidebar sections.
public enum NavigationSection: String, Identifiable, Hashable, CaseIterable, Sendable {
    case overview = "Overview"
    case platforms = "Platforms"
    case system = "Vault"

    public var id: String { rawValue }
}
