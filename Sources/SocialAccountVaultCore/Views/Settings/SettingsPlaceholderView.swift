import SwiftUI
import SwiftData

/// View managing application settings and security policies.
///
/// CATATAN JUJUR (TASK 12.2): Export JSON, Export CSV, dan Backup DB belum tersedia
/// di V1. Kontrol ditampilkan sebagai "Coming Soon" dan dinonaktifkan; tidak ada
/// action handler yang berjalan, tidak ada file/dummy output, dan tidak ada klaim
/// keberhasilan. Jangan aktifkan tombol ini sampai layanan export/backup benar-benar ada.
public struct SettingsPlaceholderView: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Vault Settings")
                        .font(.title2.weight(.bold))
                    Text("Manage security policies and upcoming portability features.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Security Policy Banner
                HStack(spacing: 16) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.green)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Strict Offline Security Invariant")
                            .font(.headline)
                        Text("Social Account Vault never stores passwords, OTPs, OAuth tokens, session cookies, or recovery codes. All operations execute strictly on your device.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.green.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.green.opacity(0.2), lineWidth: 1)
                )

                // Backup & Export Section — fitur BELUM tersedia di V1.
                VStack(alignment: .leading, spacing: 12) {
                    Text("Backup & Portability")
                        .font(.headline)

                    VStack(spacing: 8) {
                        settingsRow(
                            title: "Export JSON Archive",
                            subtitle: "Not available yet. Planned for a future release.",
                            icon: "arrow.down.doc.fill",
                            actionTitle: "Coming Soon"
                        )

                        Divider()

                        settingsRow(
                            title: "Export CSV Table",
                            subtitle: "Not available yet. Planned for a future release.",
                            icon: "tablecells.fill",
                            actionTitle: "Coming Soon"
                        )

                        Divider()

                        settingsRow(
                            title: "SQLite Database Snapshot",
                            subtitle: "Not available yet. Planned for a future release.",
                            icon: "cylinder.split.1x2.fill",
                            actionTitle: "Coming Soon"
                        )
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.secondary.opacity(0.08))
                    )
                }

                // About section
                VStack(alignment: .leading, spacing: 8) {
                    Text("About Social Account Vault")
                        .font(.headline)
                    Text("Version 1.0.0 (Native macOS)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Designed for Apple Silicon ARM64, Swift 6, SwiftUI & SwiftData.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)

                Spacer()
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private func settingsRow(
        title: String,
        subtitle: String,
        icon: String,
        actionTitle: String
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Fitur BELUM tersedia: tampilkan label status "Coming Soon".
            // Tidak ada tombol/action handler — baik yang aktif maupun kosong.
            Text(actionTitle)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                )
        }
    }
}
