import Foundation

/// Standardized, strongly typed metadata keys for `AccountDetail`.
///
/// Strategy C (Hybrid Typed Domain Intelligence): platform-specific and highly
/// variable attributes are stored as validated key-value `AccountDetail` records
/// using these canonical keys, instead of freeform strings or heavy child models.
///
/// Security Invariant:
/// These keys describe operational identifiers and context only. They must never
/// be used to store passwords, tokens, OTP seeds, recovery codes, or private keys.
/// The raw values are stable and must not be renamed once persisted.
public enum StandardMetadataKey: String, CaseIterable, Identifiable, Hashable, Sendable, Codable {
    // Platform Identifiers
    case youtubeChannelID = "platform.youtube.channel_id"
    case metaPageID = "platform.meta.page_id"
    case instagramAccountID = "platform.instagram.account_id"
    case adsensePublisherID = "platform.adsense.publisher_id"
    case shopeePartnerID = "platform.shopee.partner_id"

    // Infrastructure & DNS
    case cloudflareZoneID = "infrastructure.cloudflare.zone_id"
    case primaryNameserver = "infrastructure.dns.nameserver_1"
    case secondaryNameserver = "infrastructure.dns.nameserver_2"
    case domainRegistrar = "infrastructure.domain.registrar"

    // Monetization Details
    case payoutCurrency = "monetization.payout.currency"
    case payoutSchedule = "monetization.payout.schedule"
    case affiliateNiche = "monetization.affiliate.niche"

    // Device Context
    case workstationLocation = "device.workstation.location"
    case browserProfileName = "device.browser.profile"

    public var id: String { rawValue }

    /// The functional domain category this key belongs to.
    public var category: MetadataCategory {
        switch self {
        case .youtubeChannelID, .metaPageID, .instagramAccountID, .adsensePublisherID, .shopeePartnerID:
            return .platformIdentifier
        case .cloudflareZoneID, .primaryNameserver, .secondaryNameserver, .domainRegistrar:
            return .infrastructure
        case .payoutCurrency, .payoutSchedule, .affiliateNiche:
            return .monetization
        case .workstationLocation, .browserProfileName:
            return .deviceContext
        }
    }
}