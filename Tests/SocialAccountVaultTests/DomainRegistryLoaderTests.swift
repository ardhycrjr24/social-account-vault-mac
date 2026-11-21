import Testing
import Foundation
@testable import SocialAccountVaultCore

/// TASK 10.3 — DomainRegistry JSON resource tests.
/// Resource test terisolasi; tidak ada domain produksi yang ditambahkan.
@Suite("Domain Registry Resource Loader")
struct DomainRegistryLoaderTests {
    private let validator = URLSafetyValidator()

    private func tempJSON(_ string: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault_domains_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("OfficialDomains.json")
        try Data(string.utf8).write(to: url)
        return url
    }

    // 1. Resource valid berhasil dimuat.
    @Test("1. Valid JSON resource loads with normalized hostnames")
    func testValidResourceLoads() throws {
        let url = try tempJSON(#"{"version":1,"platforms":{"YouTube":["Youtube.COM","studio.youtube.com"]}}"#)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let result = DomainRegistryLoader.load(from: url)
        #expect(result.diagnostic == nil)
        #expect(result.registry.domains(for: "YouTube") == ["youtube.com", "studio.youtube.com"])
    }

    // 2. Resource kosong → registry kosong.
    @Test("2. Empty platforms produce empty registry")
    func testEmptyResource() throws {
        let url = try tempJSON(#"{"version":1,"platforms":{"example-platform":[]}}"#)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let result = DomainRegistryLoader.load(from: url)
        #expect(result.diagnostic == nil)
        #expect(result.registry.domains(for: "example-platform").isEmpty)
    }

    // 3. Resource hilang ditangani aman.
    @Test("3. Missing resource returns empty registry with diagnostic")
    func testMissingResource() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault_missing_\(UUID().uuidString).json")
        let result = DomainRegistryLoader.load(from: missing)
        #expect(result.registry.domains(for: "YouTube").isEmpty)
        #expect(result.diagnostic != nil)
    }

    // 4. JSON malformed ditangani aman.
    @Test("4. Malformed JSON returns empty registry")
    func testMalformedJSON() throws {
        let url = try tempJSON("{ this is not json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let result = DomainRegistryLoader.load(from: url)
        #expect(result.registry.domains(for: "YouTube").isEmpty)
        #expect(result.diagnostic != nil)
    }

    // 5. Hostname malformed ditolak.
    @Test("5. Malformed hostnames are rejected")
    func testMalformedHostnames() throws {
        for bad in ["not a host", "-bad.example.com", "example.com-", "http://example.com", "user@example.com"] {
            let json = "{\"version\":1,\"platforms\":{\"P\":[\"\(bad)\"]}}"
            let result = DomainRegistryLoader.parse(Data(json.utf8))
            #expect(result.registry.domains(for: "P").isEmpty, "\(bad) harus ditolak")
            #expect(result.diagnostic != nil)
        }
    }

    // 6. Wildcard ditolak.
    @Test("6. Wildcard hostname is rejected")
    func testWildcardRejected() throws {
        let result = DomainRegistryLoader.parse(Data(#"{"version":1,"platforms":{"P":["*.example.com"]}}"#.utf8))
        #expect(result.registry.domains(for: "P").isEmpty)
        #expect(result.diagnostic != nil)
    }

    // 7. Exact match.
    @Test("7. Exact hostname match")
    func testExactMatch() {
        let reg = DomainRegistry(allowedDomains: ["P": ["example.com"]])
        #expect(validator.matchesAllowedDomain("example.com", platform: "P", registry: reg))
    }

    // 8. Dot-boundary suffix match.
    @Test("8. Dot-boundary suffix match")
    func testDotBoundary() {
        let reg = DomainRegistry(allowedDomains: ["P": ["example.com"]])
        #expect(validator.matchesAllowedDomain("studio.example.com", platform: "P", registry: reg))
    }

    // 9. Domain mirip tidak dianggap cocok.
    @Test("9. Similar-looking domain is not a match")
    func testFakeSuffix() {
        let reg = DomainRegistry(allowedDomains: ["P": ["example.com"]])
        #expect(!validator.matchesAllowedDomain("example.com.attacker.test", platform: "P", registry: reg))
        #expect(!validator.matchesAllowedDomain("fakeexample.com", platform: "P", registry: reg))
    }

    // 10. Domain tidak dikenal tetap WARNING.
    @Test("10. Unknown domain remains WARNING")
    func testUnknownDomainWarning() {
        let d = validator.classify("https://unknown.test", platform: "P",
                                   registry: DomainRegistry(allowedDomains: ["P": ["example.com"]]))
        if case .warning = d { /* expected */ } else { Issue.record("expected warning") }
    }

    // 11. specificationExamples tidak masuk registry produksi.
    @Test("11. specificationExamples is not the production registry")
    func testExamplesNotProduction() throws {
        let url = try tempJSON(#"{"version":1,"platforms":{"example-platform":[]}}"#)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let production = DomainRegistryLoader.load(from: url).registry
        #expect(production != DomainRegistry.specificationExamples)
        #expect(production.domains(for: "YouTube").isEmpty)
    }

    // 12. SafeLinkButton tetap memakai validator (source-level audit).
    @Test("12. SafeLinkButton still routes through validator")
    func testSafeLinkUsesValidator() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file = root.appendingPathComponent("Sources/SocialAccountVaultCore/Views/Components/SafeLinkButton.swift")
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("URLSafetyValidator().classify"))
        #expect(text.contains("NSWorkspace.shared.open"))
    }
}
