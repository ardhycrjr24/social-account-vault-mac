import Foundation
import SwiftUI

/// Environment injection untuk konfigurasi domain. Default KOSONG (fail-closed).
public struct DomainRegistryKey: EnvironmentKey {
    public static let defaultValue = DomainRegistry()
}

extension EnvironmentValues {
    public var domainRegistry: DomainRegistry {
        get { self[DomainRegistryKey.self] }
        set { self[DomainRegistryKey.self] = newValue }
    }
}

/// Klasifikasi hasil evaluasi URL. Bukan jaminan situs aman —
/// `safeToOpen` hanya berarti aturan teknis & kebijakan terpenuhi.
public enum URLSafetyDecision: Sendable, Equatable {
    case safeToOpen(url: URL, hostname: String)
    case warning(url: URL, hostname: String, reasons: [String])
    case blocked(reasons: [String])

    public var isOpenable: Bool {
        switch self {
        case .safeToOpen, .warning: return true
        case .blocked: return false
        }
    }

    public var hostname: String? {
        switch self {
        case .safeToOpen(_, let host), .warning(_, let host, _): return host
        case .blocked: return nil
        }
    }

    public var reasons: [String] {
        switch self {
        case .safeToOpen: return []
        case .warning(_, _, let reasons), .blocked(let reasons): return reasons
        }
    }
}

/// Registry domain resmi — DIPISAHKAN dari algoritma validator.
///
/// Spesifikasi menyebut "official allowlist" tetapi tidak menyediakan daftar
/// lengkap; hanya contoh ilustratif. Registry default KOSONG (fail-closed):
/// semua URL HTTPS menjadi WARNING sampai produk memutuskan daftar domain.
/// Jangan mengisi registry berdasarkan asumsi.
public struct DomainRegistry: Sendable, Equatable {
    public let allowedDomains: [String: [String]]

    public init(allowedDomains: [String: [String]] = [:]) {
        self.allowedDomains = allowedDomains
    }

    /// Contoh hanya untuk pengujian/demonstrasi sesuai dokumen spesifikasi.
    /// BUKAN daftar produksi; tidak dipakai otomatis oleh aplikasi.
    public static let specificationExamples = DomainRegistry(allowedDomains: [
        "YouTube": ["youtube.com"],
        "Instagram": ["instagram.com"],
        "Facebook": ["facebook.com"],
        "TikTok": ["tiktok.com"],
    ])

    public func domains(for platform: String) -> [String] {
        allowedDomains[platform] ?? []
    }
}

/// Validator URL terpusat. Murni, tidak membuka URL, tidak bergantung jaringan.
public struct URLSafetyValidator: Sendable {
    public init() {}

    /// Klasifikasi string URL mentah.
    /// - Parameters:
    ///   - rawValue: input pengguna/penyimpanan.
    ///   - platform: platform akun untuk pencocokan allowlist.
    ///   - registry: daftar domain resmi (pisahan konfigurasi).
    ///   - acceptsHTTP: hanya true bila konteks eksplisit mengizinkan HTTP
    ///     (mis. metadata lama); hasil tetap WARNING.
    public func classify(
        _ rawValue: String,
        platform: String? = nil,
        registry: DomainRegistry = DomainRegistry(),
        acceptsHTTP: Bool = false
    ) -> URLSafetyDecision {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .blocked(reasons: ["URL kosong"])
        }

        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let rawHost = components.host, !rawHost.isEmpty else {
            return .blocked(reasons: ["URL tidak valid atau tidak memiliki hostname"])
        }

        // Skema: hanya HTTPS. HTTP opsional & selalu WARNING.
        guard scheme == "https" || (acceptsHTTP && scheme == "http") else {
            return .blocked(reasons: ["Skema '\(scheme)' tidak diizinkan"])
        }

        // Userinfo / authority injection ditolak keras.
        if components.user != nil || components.password != nil {
            return .blocked(reasons: ["URL mengandung userinfo yang mencurigakan"])
        }

        let host = rawHost.lowercased()

        // IP address langsung ditolak (bukan domain resmi yang dapat diverifikasi).
        if isIPAddress(host) {
            return .blocked(reasons: ["URL menggunakan alamat IP langsung"])
        }

        // IDN/Punycode & homograph: flag untuk perhatian pengguna.
        var warnings: [String] = []
        if host.contains("xn--") || host.utf8.contains(where: { $0 > 127 }) {
            warnings.append("Hostname menggunakan Punycode/IDN yang dapat menyamar sebagai domain lain")
        }
        if scheme == "http" {
            warnings.append("URL menggunakan HTTP (tidak terenkripsi)")
        }

        // Port: non-default flagged; port jelas invalid diblokir.
        if let port = components.port {
            if port <= 0 || port > 65535 {
                return .blocked(reasons: ["Port tidak valid"])
            }
            if scheme == "https" && port != 443 {
                warnings.append("URL menggunakan port non-standar \(port)")
            }
        }

        // Subdomain bertingkat yang tidak dikenali (hanya bila platform tersedia).
        if let platform,
           !host.hasPrefix("www."),
           host.split(separator: ".").count > 3,
           !matchesAllowedDomain(host, platform: platform, registry: registry) {
            warnings.append("Subdomain bertingkat yang tidak dikenali")
        }

        guard let url = components.url else {
            return .blocked(reasons: ["URL tidak dapat dibangun"])
        }

        // Dot-boundary matching ke allowlist. Tidak memakai substring hostname.
        if let platform, !registry.domains(for: platform).isEmpty {
            if matchesAllowedDomain(host, platform: platform, registry: registry) {
                if warnings.isEmpty {
                    return .safeToOpen(url: url, hostname: host)
                }
                return .warning(url: url, hostname: host, reasons: warnings)
            }
            warnings.append("Hostname tidak cocok dengan domain resmi platform '\(platform)'")
        } else {
            warnings.append("Tidak ada domain resmi terdaftar untuk platform ini")
        }

        return .warning(url: url, hostname: host, reasons: warnings)
    }

    /// Dot-boundary: `youtube.com`, `studio.youtube.com` cocok;
    /// `fakeyoutube.com`, `youtube.com.attacker.com` TIDAK cocok.
    public func matchesAllowedDomain(_ host: String, platform: String, registry: DomainRegistry) -> Bool {
        let normalized = host.lowercased()
        for domain in registry.domains(for: platform) {
            let allowed = domain.lowercased()
            if normalized == allowed { return true }
            if normalized.hasSuffix("." + allowed) { return true }
        }
        return false
    }

    private func isIPAddress(_ host: String) -> Bool {
        // IPv4
        let parts = host.split(separator: ".")
        if parts.count == 4, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) {
            return true
        }
        // IPv6 literal [....]
        if host.hasPrefix("[") && host.hasSuffix("]") { return true }
        return false
    }
}
