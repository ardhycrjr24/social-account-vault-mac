import Foundation

/// Hasil pemuatan registry dari resource JSON.
/// Diagnostic bersifat generik — tidak memuat konten resource atau data sensitif.
public struct DomainRegistryLoadResult: Sendable, Equatable {
    public let registry: DomainRegistry
    public let diagnostic: String?

    public init(registry: DomainRegistry, diagnostic: String? = nil) {
        self.registry = registry
        self.diagnostic = diagnostic
    }
}

/// Loader untuk `OfficialDomains.json` dari resource bundle.
///
/// - Tidak melakukan network request.
/// - Tidak mengubah `URLSafetyValidator` atau keputusan keamanannya.
/// - Jika resource hilang/malformed: mengembalikan registry KOSONG + diagnostic,
///   TIDAK fallback ke `specificationExamples` dan TIDAK menganggap domain aman.
public enum DomainRegistryLoader: Sendable {
    public static let resourceName = "OfficialDomains"
    public static let resourceExtension = "json"

    /// Memuat dari bundle.
    ///
    /// - SwiftPM: `Bundle.module` (resource terproses otomatis).
    /// - Xcode project: framework `SocialAccountVaultCore.framework` menampung resource
    ///   di `Resources/OfficialDomains.json`; `Bundle.module` tidak tersedia, jadi
    ///   cari bundle berdasarkan tipe kelas ini (resource satu-satunya di bundle itu).
    /// Fail-closed: bila resource tak ditemukan, registry KOSONG + diagnostic.
    public static func load() -> DomainRegistryLoadResult {
#if SWIFT_PACKAGE
        // SwiftPM: resource terproses otomatis ke Bundle.module.
        if let moduleURL = Bundle.module.url(
            forResource: resourceName,
            withExtension: resourceExtension
        ) {
            return load(from: moduleURL)
        }
#endif
        // Xcode project (tanpa SwiftPM): cari resource di SEMUA bundle yang
        // terdaftar. Resource dipasang di app bundle (`Contents/Resources`), sedangkan
        // kode ini berada di framework Core — jadi `Bundle(for:)` saja tidak cukup.
        let candidates = [
            Bundle(for: ResourceAnchor.self),
            Bundle.main,
        ] + Bundle.allBundles + Bundle.allFrameworks
        for bundle in candidates {
            if let url = bundle.url(forResource: resourceName, withExtension: resourceExtension) {
                return load(from: url)
            }
        }
        return DomainRegistryLoadResult(
            registry: DomainRegistry(),
            diagnostic: "Official domain resource is unavailable; using an empty allowlist."
        )
    }

    /// Anchor kelas untuk menemukan bundle pemilik resource (Xcode project).
    private final class ResourceAnchor {}

    /// Memuat dari URL tertentu (digunakan test dengan resource terisolasi).
    public static func load(from url: URL) -> DomainRegistryLoadResult {
        guard let data = try? Data(contentsOf: url) else {
            return DomainRegistryLoadResult(
                registry: DomainRegistry(),
                diagnostic: "Official domain resource could not be read; using an empty allowlist."
            )
        }
        return parse(data)
    }

    /// Parsing murni — dapat dipakai test dengan data JSON buatan.
    public static func parse(_ data: Data) -> DomainRegistryLoadResult {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else {
            return emptyWithDiagnostic("Official domain resource has an invalid structure.")
        }

        guard let version = root["version"] as? Int, version == 1 else {
            return emptyWithDiagnostic("Official domain resource has an unsupported version.")
        }
        guard let platforms = root["platforms"] as? [String: [String]] else {
            return emptyWithDiagnostic("Official domain resource has invalid platform entries.")
        }

        var normalized: [String: [String]] = [:]
        for (rawPlatform, rawDomains) in platforms {
            let platform = rawPlatform.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !platform.isEmpty else {
                return emptyWithDiagnostic("Official domain resource contains an empty platform name.")
            }
            var accepted: [String] = []
            for rawDomain in rawDomains {
                guard let host = normalizeHostname(rawDomain) else {
                    return emptyWithDiagnostic("Official domain resource contains an invalid hostname.")
                }
                if !accepted.contains(host) { accepted.append(host) }
            }
            normalized[platform] = accepted
        }

        return DomainRegistryLoadResult(registry: DomainRegistry(allowedDomains: normalized))
    }

    // MARK: - Hostname validation

    /// Menerima HANYA hostname polos (huruf, angka, titik, hyphen).
    /// Menolak scheme, path, port, credential, wildcard, spasi, dan IDN/Punycode.
    private static func normalizeHostname(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        guard !value.contains("*") else { return nil }           // wildcard tidak didukung
        guard !value.contains("/") else { return nil }           // path
        guard !value.contains(":") else { return nil }           // scheme / port
        guard !value.contains("@") else { return nil }           // userinfo
        guard !value.contains(" ") else { return nil }
        guard !value.contains("xn--") else { return nil }        // IDN/Punycode tidak diverifikasi

        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        guard value.allSatisfy({ allowed.contains($0) }) else { return nil }

        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return nil }
        guard labels.allSatisfy({ !$0.isEmpty && !$0.hasPrefix("-") && !$0.hasSuffix("-") }) else {
            return nil
        }

        return value.lowercased()
    }

    private static func emptyWithDiagnostic(_ message: String) -> DomainRegistryLoadResult {
        DomainRegistryLoadResult(
            registry: DomainRegistry(),
            diagnostic: "\(message) Using an empty allowlist."
        )
    }
}
