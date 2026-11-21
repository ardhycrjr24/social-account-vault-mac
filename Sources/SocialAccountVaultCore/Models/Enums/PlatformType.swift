import Foundation

/// Core digital platform categories supported by Social Account Vault.
public enum PlatformType: String, Identifiable, Hashable, CaseIterable, Sendable, Codable {
    case youtube = "YouTube"
    case instagram = "Instagram"
    case tiktok = "TikTok"
    case facebook = "Facebook"
    case email = "Email"
    case shopeeAffiliate = "Shopee Affiliate"
    case googleAdSense = "Google AdSense"
    case websiteDomain = "Website & Domain"

    public var id: String { rawValue }

    /// SF Symbol icon name for the platform.
    public var iconName: String {
        switch self {
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
        case .shopeeAffiliate:
            return "cart.fill"
        case .googleAdSense:
            return "chart.line.uptrend.xyaxis"
        case .websiteDomain:
            return "globe"
        }
    }

    /// Official web dashboard URL suggestion for quick browser access.
    public var defaultDashboardURL: String {
        switch self {
        case .youtube:
            return "https://studio.youtube.com"
        case .instagram:
            return "https://www.instagram.com"
        case .tiktok:
            return "https://www.tiktok.com"
        case .facebook:
            return "https://business.facebook.com"
        case .email:
            return "https://mail.google.com"
        case .shopeeAffiliate:
            return "https://affiliate.shopee.co.id"
        case .googleAdSense:
            return "https://www.google.com/adsense"
        case .websiteDomain:
            return "https://dash.cloudflare.com"
        }
    }

    /// Default display ordering in listings.
    public var defaultOrder: Int {
        switch self {
        case .youtube: return 1
        case .instagram: return 2
        case .tiktok: return 3
        case .facebook: return 4
        case .email: return 5
        case .shopeeAffiliate: return 6
        case .googleAdSense: return 7
        case .websiteDomain: return 8
        }
    }
}
