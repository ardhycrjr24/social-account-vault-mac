import Testing
import Foundation
@testable import SocialAccountVaultCore

/// TASK 12.3 — DomainRegistry V1 official domain verification tests.
///
/// Hanya 4 platform: YouTube, Instagram, Facebook, TikTok.
/// Root domain kanonik diverifikasi dari sumber resmi (lihat laporan audit).
@Suite("Domain Registry V1 Official Domains")
struct DomainRegistryV1Tests {
    private let validator = URLSafetyValidator()

    /// Resource produksi apa adanya (dibaca dari repo, bukan fixture buatan).
    private func productionResourceURL() throws -> URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SocialAccountVaultTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
        let url = root.appendingPathComponent("Sources/SocialAccountVaultCore/Resources/OfficialDomains.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            Issue.record("production resource missing")
            throw CocoaError(.fileNoSuchFile)
        }
        return url
    }

    @Test("Production registry loads with exactly four verified platforms")
    func testProductionFourPlatforms() throws {
        let result = DomainRegistryLoader.load(from: try productionResourceURL())
        #expect(result.diagnostic == nil)
        #expect(result.registry.domains(for: "YouTube") == ["youtube.com"])
        #expect(result.registry.domains(for: "Instagram") == ["instagram.com"])
        #expect(result.registry.domains(for: "Facebook") == ["facebook.com"])
        #expect(result.registry.domains(for: "TikTok") == ["tiktok.com"])
    }

    @Test("All four canonical roots are accepted as safeToOpen")
    func testCanonicalRootsAccepted() throws {
        let registry = DomainRegistryLoader.load(from: try productionResourceURL()).registry
        for (platform, host) in [
            ("YouTube", "youtube.com"),
            ("Instagram", "instagram.com"),
            ("Facebook", "facebook.com"),
            ("TikTok", "tiktok.com"),
        ] {
            if case .safeToOpen(let url, let h) = validator.classify(
                "https://\(host)/", platform: platform, registry: registry
            ) {
                #expect(h == host)
                #expect(url.host == host)
            } else {
                Issue.record("\(host) harus safeToOpen untuk \(platform)")
            }
        }
    }

    @Test("Official subdomains match via dot-boundary")
    func testSubdomainsAccepted() throws {
        let registry = DomainRegistryLoader.load(from: try productionResourceURL()).registry
        for (platform, host) in [
            ("YouTube", "studio.youtube.com"),
            ("YouTube", "m.youtube.com"),
            ("Instagram", "www.instagram.com"),
            ("Facebook", "business.facebook.com"),
            ("TikTok", "ads.tiktok.com"),
        ] {
            if case .safeToOpen = validator.classify(
                "https://\(host)/", platform: platform, registry: registry
            ) { /* ok */ } else {
                Issue.record("\(host) harus cocok dot-boundary")
            }
        }
    }

    @Test("Fake suffixes are rejected")
    func testFakeSuffixRejected() throws {
        let registry = DomainRegistryLoader.load(from: try productionResourceURL()).registry
        for (platform, host) in [
            ("YouTube", "fakeyoutube.com"),
            ("YouTube", "youtube.com.attacker.test"),
            ("Instagram", "notinstagram.com"),
            ("TikTok", "tiktok.com.evil.test"),
        ] {
            if case .safeToOpen = validator.classify(
                "https://\(host)/", platform: platform, registry: registry
            ) {
                Issue.record("\(host) fake suffix TIDAK boleh safeToOpen")
            }
        }
    }

    @Test("Unlisted platform domains remain WARNING")
    func testUnlistedWarning() throws {
        let registry = DomainRegistryLoader.load(from: try productionResourceURL()).registry
        // Platform di luar 4 yang disetujui -> registry kosong -> WARNING.
        if case .warning = validator.classify(
            "https://shopee.co.id/", platform: "Shopee Affiliate", registry: registry
        ) { /* expected */ } else { Issue.record("platform tak terdaftar harus WARNING") }

        if case .warning = validator.classify(
            "https://google.com/", platform: "Google AdSense", registry: registry
        ) { /* expected */ } else { Issue.record("google.com untuk AdSense tak terdaftar -> WARNING") }
    }

    @Test("Userinfo is still rejected even for allowed root")
    func testUserinfoRejected() throws {
        let registry = DomainRegistryLoader.load(from: try productionResourceURL()).registry
        if case .blocked = validator.classify(
            "https://***@youtube.com/", platform: "YouTube", registry: registry
        ) { /* expected */ } else { Issue.record("userinfo harus diblokir") }
    }

    @Test("No wildcard and no extra domains were added")
    func testOnlyFourDomains() throws {
        let registry = DomainRegistryLoader.load(from: try productionResourceURL()).registry
        var all: [String] = []
        for p in ["YouTube", "Instagram", "Facebook", "TikTok"] { all += registry.domains(for: p) }
        #expect(all.sorted() == ["facebook.com", "instagram.com", "tiktok.com", "youtube.com"])
        #expect(!all.contains("*"))
        // Tak ada accounts.google.com / shortener / CDN yang menyelinap.
        #expect(!all.contains("accounts.google.com"))
        #expect(!all.contains(where: { $0.contains("bit.ly") || $0.contains("t.co") }))
    }

    @Test("Malformed resource stays fail-closed")
    func testMalformedFailClosed() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault_domv1_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("OfficialDomains.json")
        try Data("{ not json".utf8).write(to: url)
        let result = DomainRegistryLoader.load(from: url)
        #expect(result.diagnostic != nil)
        #expect(result.registry.domains(for: "YouTube").isEmpty)
    }
}