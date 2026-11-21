import Testing
import Foundation

/// TASK 12.2 — Settings export/backup UI honesty tests.
///
/// Bukti berbasis source (tanpa host SwiftUI): memastikan kontrol export/backup
/// yang belum tersedia TIDAK dipresentasikan sebagai fitur aktif, tombolnya
/// dinonaktifkan/tidak ada action handler, dan tidak ada klaim keberhasilan.
@Suite("Settings Export & Backup UI Honesty")
struct SettingsHonestyTests {
    private var source: String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SocialAccountVaultTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
        let path = root.appendingPathComponent("Sources/SocialAccountVaultCore/Views/Settings/SettingsPlaceholderView.swift")
        return (try? String(contentsOf: path, encoding: .utf8)) ?? ""
    }

    @Test("Source loads")
    func testSourceLoads() {
        #expect(!source.isEmpty)
    }

    @Test("Export/Backup controls marked Coming Soon and not available")
    func testControlsMarkedUnavailable() throws {
        #expect(source.contains("\"Coming Soon\""))
        let rows = [
            "Export JSON Archive",
            "Export CSV Table",
            "SQLite Database Snapshot"
        ]
        for title in rows {
            #expect(source.contains(title))
        }
        // Tidak ada parameter/flag 'available' yang menandai fitur aktif.
        #expect(!source.contains("isAvailable"))
    }

    @Test("No enabled Button with empty action remains")
    func testNoActiveEmptyButton() throws {
        // Button(actionTitle) {} yang aktif berarti aksi kosong tapi tampak fitur.
        #expect(!source.contains("Button(actionTitle) {}"))
    }

    @Test("Unavailable controls render a status label, not a tappable control")
    func testUnavailableRendersLabel() throws {
        #expect(source.contains("Text(actionTitle)"))
        #expect(!source.contains("Button(actionTitle)"))
    }

    @Test("No success/portability promise in copy")
    func testCopyHasNoSuccessClaim() throws {
        #expect(!source.lowercased().contains("create a complete, portable json export"))
        #expect(!source.lowercased().contains("generate a spreadsheet-compatible summary"))
        #expect(!source.lowercased().contains("direct snapshot of the local swiftdata sqlite database"))
        #expect(source.contains("Not available yet."))
    }

    @Test("Navigation sections still present")
    func testStructureIntact() throws {
        #expect(source.contains("Vault Settings"))
        #expect(source.contains("Backup & Portability"))
        #expect(source.contains("About Social Account Vault"))
        #expect(source.contains("Strict Offline Security Invariant"))
    }
}