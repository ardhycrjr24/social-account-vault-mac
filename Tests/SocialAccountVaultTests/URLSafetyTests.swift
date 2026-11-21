import Testing
import Foundation
@testable import SocialAccountVaultCore

/// Task 1 — URL Safety & Anti-Phishing regression tests.
/// Deterministik, tanpa jaringan, tanpa membuka website sungguhan.
@Suite("URL Safety & Anti-Phishing")
struct URLSafetyTests {
    private let validator = URLSafetyValidator()
    private let registry = DomainRegistry.specificationExamples

    private func classify(_ value: String, acceptsHTTP: Bool = false) -> URLSafetyDecision {
        validator.classify(value, platform: "YouTube", registry: registry, acceptsHTTP: acceptsHTTP)
    }

    // 1. HTTPS valid + allowlist -> SAFE.
    @Test("1. HTTPS valid on allowlisted domain is SAFE")
    func testHTTPSValid() {
        let d = classify("https://youtube.com/watch?v=1")
        guard case .safeToOpen(_, let host) = d else {
            Issue.record("expected safe, got \(d)"); return
        }
        #expect(host == "youtube.com")
    }

    // 2. HTTP ditolak default; WARNING bila eksplisit diizinkan.
    @Test("2. HTTP blocked by default, warning when explicitly accepted")
    func testHTTPHandling() {
        #expect(classify("http://youtube.com").isOpenable == false)
        if case .warning(_, _, let reasons) = classify("http://youtube.com", acceptsHTTP: true) {
            #expect(reasons.contains { $0.contains("HTTP") })
        } else {
            Issue.record("expected warning for accepted HTTP")
        }
    }

    // 3. Tanpa hostname.
    @Test("3. URL without hostname is BLOCKED")
    func testNoHostname() {
        #expect(classify("https:///path").isOpenable == false)
        #expect(classify("https://").isOpenable == false)
    }

    // 4. Malformed.
    @Test("4. Malformed URL is BLOCKED")
    func testMalformed() {
        #expect(classify("not a url at all").isOpenable == false)
        #expect(classify("https://exa mple.com").isOpenable == false)
    }

    // 5-8. Skema berbahaya.
    @Test("5-8. Dangerous schemes are BLOCKED")
    func testDangerousSchemes() {
        for value in ["javascript:alert(1)", "data:text/html,<script>", "file:///etc/passwd", "ftp://example.com"] {
            let d = classify(value)
            #expect(!d.isOpenable, "\(value) harus diblokir")
        }
    }

    // 9. Userinfo.
    @Test("9. URL with userinfo is BLOCKED")
    func testUserinfo() {
        #expect(classify("https://***@attacker.com/").isOpenable == false)
        #expect(classify("https://user:pass@youtube.com/").isOpenable == false)
    }

    // 10. Exact match.
    @Test("10. Exact hostname match")
    func testExactMatch() {
        #expect(validator.matchesAllowedDomain("youtube.com", platform: "YouTube", registry: registry))
        #expect(!validator.matchesAllowedDomain("youtube.com", platform: "Instagram", registry: registry))
    }

    // 11. Fake suffix.
    @Test("11. Fake suffix domains are NOT allowlisted")
    func testFakeSuffix() {
        #expect(!validator.matchesAllowedDomain("fakeyoutube.com", platform: "YouTube", registry: registry))
        #expect(!validator.matchesAllowedDomain("youtube.com.attacker.com", platform: "YouTube", registry: registry))
        #expect(classify("https://youtube.com.attacker.com").isOpenable == true) // WARNING, bukan SAFE
        if case .safeToOpen = classify("https://youtube.com.attacker.com") {
            Issue.record("fake suffix tidak boleh SAFE")
        }
    }

    // 12. Dot boundary.
    @Test("12. Valid dot-delimited subdomain matches; boundary enforced")
    func testDotBoundary() {
        #expect(validator.matchesAllowedDomain("studio.youtube.com", platform: "YouTube", registry: registry))
        #expect(validator.matchesAllowedDomain("m.youtube.com", platform: "YouTube", registry: registry))
        if case .safeToOpen = classify("https://studio.youtube.com") {
            // expected
        } else {
            Issue.record("studio.youtube.com harus SAFE")
        }
    }

    // 13. Punycode.
    @Test("13. Punycode / IDN is flagged as WARNING")
    func testPunycode() {
        let d = classify("https://xn--youtube-c4a.com")
        if case .warning(_, _, let reasons) = d {
            #expect(reasons.contains { $0.contains("Punycode") || $0.contains("IDN") })
        } else {
            Issue.record("Punycode harus WARNING, bukan \(d)")
        }
    }

    // 14. Homograph yang dapat dikenali heuristics (Punycode bentuk homograf).
    @Test("14. Recognizable homograph is flagged")
    func testHomograph() {
        let d = classify("https://уоutube.com") // Cyrillic о/у
        #expect(!d.isOpenable || {
            if case .warning = d { return true }
            return false
        }(), "homograph harus WARNING atau BLOCKED")
    }

    // 15. IP address.
    @Test("15. Direct IP address is BLOCKED")
    func testIPAddress() {
        #expect(classify("https://192.168.1.1").isOpenable == false)
        #expect(classify("https://8.8.8.8/login").isOpenable == false)
    }

    // 16. Port invalid / non-standard.
    @Test("16. Invalid port BLOCKED, non-standard port WARNING")
    func testPorts() {
        #expect(classify("https://youtube.com:99999").isOpenable == false)
        let d = classify("https://youtube.com:8443")
        if case .warning(_, _, let reasons) = d {
            #expect(reasons.contains { $0.contains("8443") })
        } else {
            Issue.record("port 8443 harus WARNING")
        }
    }

    // 17. Empty directLoginURLString.
    @Test("17. Empty direct login string is BLOCKED")
    func testEmptyDirectLogin() {
        #expect(classify("").isOpenable == false)
        #expect(classify("   ").isOpenable == false)
    }

    // 18. WARNING memerlukan konfirmasi (decision tidak otomatis open).
    @Test("18. WARNING carries reasons for explicit confirmation")
    func testWarningRequiresConfirmation() {
        let d = classify("https://unknown-example.test") // tidak ada di allowlist
        if case .warning(_, let host, let reasons) = d {
            #expect(host == "unknown-example.test")
            #expect(!reasons.isEmpty)
        } else {
            Issue.record("expected WARNING, got \(d)")
        }
    }

    // 19. BLOCKED tidak dapat dibuka.
    @Test("19. BLOCKED decision is never openable")
    func testBlockedNotOpenable() {
        for value in ["javascript:alert(1)", "ftp://x.com", "https://user@x.com", ""] {
            let d = classify(value)
            #expect(!d.isOpenable)
            if case .blocked = d { /* expected */ }
            else { Issue.record("\(value) harus .blocked") }
        }
    }

    // 20. Tidak ada jalur NSWorkspace.shared.open yang melewati validator
    // (dicek secara statis oleh scripts/verify_code_integrity.py).
    @Test("20. No unvalidated NSWorkspace.open path exists in source")
    func testNoUnvalidatedOpenPath() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources")
        let enumerator = FileManager.default.enumerator(
            at: sources,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )!
        var offenders: [String] = []
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            let lines = text.split(separator: "\n")
            for (index, line) in lines.enumerated() where line.contains("NSWorkspace.shared.open") {
                let window = lines[max(0, index - 8)..<min(lines.count, index + 1)].joined(separator: "\n")
                // Jalur yang aman: di SafeLinkButton (setelah decision) atau
                // di App help (setelah classify + confirmation).
                let isSafePath = file.lastPathComponent == "SafeLinkButton.swift"
                    || (window.contains("URLSafetyValidator") || window.contains("decision.isOpenable"))
                if !isSafePath {
                    offenders.append("\(file.lastPathComponent):\(index + 1)")
                }
            }
        }
        #expect(offenders.isEmpty, "Unvalidated open sites: \(offenders)")
    }
}
