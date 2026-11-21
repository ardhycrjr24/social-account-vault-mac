import SwiftUI
import AppKit

/// Satu-satunya jalur UI yang boleh membuka URL eksternal.
///
/// - SAFE_TO_OPEN: langsung dibuka.
/// - WARNING: menampilkan hostname + alasan, meminta konfirmasi eksplisit.
/// - BLOCKED: tombol dinonaktifkan, URL tidak pernah dibuka.
/// - `safeToOpen` BUKAN jaminan situs aman; indikator dibedakan visual.
@MainActor
public struct SafeLinkButton: View {
    public let title: String
    public let urlString: String
    public let platform: String?
    public let registry: DomainRegistry
    public let acceptsHTTP: Bool
    public let systemImage: String
    public let prominent: Bool

    @State private var pendingDecision: URLSafetyDecision?
    @State private var isShowingConfirmation = false
    @State private var lastError: String?

    public init(
        title: String,
        urlString: String,
        platform: String? = nil,
        registry: DomainRegistry = DomainRegistry(),
        acceptsHTTP: Bool = false,
        systemImage: String = "arrow.up.right.square",
        prominent: Bool = false
    ) {
        self.title = title
        self.urlString = urlString
        self.platform = platform
        self.registry = registry
        self.acceptsHTTP = acceptsHTTP
        self.systemImage = systemImage
        self.prominent = prominent
    }

    private var decision: URLSafetyDecision {
        URLSafetyValidator().classify(
            urlString,
            platform: platform,
            registry: registry,
            acceptsHTTP: acceptsHTTP
        )
    }

    @ViewBuilder
    private var styledButton: some View {
        if prominent {
            Button(action: handleTap) { Label(title, systemImage: systemImage) }
                .buttonStyle(.borderedProminent)
        } else {
            Button(action: handleTap) { Label(title, systemImage: systemImage) }
                .buttonStyle(.bordered)
        }
    }

    public var body: some View {
        styledButton
            .disabled(!decision.isOpenable)
            .help(helpText)
            .alert("Periksa tautan sebelum membuka", isPresented: $isShowingConfirmation) {
                Button("Batal", role: .cancel) { pendingDecision = nil }
                Button("Tetap Buka", role: .destructive) {
                    if let pendingDecision { open(pendingDecision) }
                    pendingDecision = nil
                }
            } message: {
                Text(alertMessage)
            }
            .alert("Tautan diblokir", isPresented: .constant(lastError != nil)) {
                Button("OK", role: .cancel) { lastError = nil }
            } message: {
                Text(lastError ?? "")
            }
    }

    private var helpText: String {
        switch decision {
        case .safeToOpen(_, let host):
            return "Buka https://\(host) di browser sistem"
        case .warning(_, let host, let reasons):
            return "Perlu konfirmasi: \(host). \(reasons.joined(separator: " "))"
        case .blocked(let reasons):
            return "Diblokir: \(reasons.joined(separator: " "))"
        }
    }

    private var alertMessage: String {
        guard let decision = pendingDecision, let host = decision.hostname else {
            return "Tautan tidak dapat dibuka."
        }
        return "Hostname: \(host)\n\n\(decision.reasons.joined(separator: "\n"))\n\nTautan ini tidak terverifikasi. Hanya lanjutkan jika Anda yakin."
    }

    private func handleTap() {
        switch decision {
        case .safeToOpen(let url, _):
            open(.safeToOpen(url: url, hostname: ""))
        case .warning:
            pendingDecision = decision
            isShowingConfirmation = true
        case .blocked(let reasons):
            lastError = reasons.joined(separator: " ")
        }
    }

    private func open(_ decision: URLSafetyDecision) {
        guard decision.isOpenable else { return }
        switch decision {
        case .safeToOpen(let url, _), .warning(let url, _, _):
            NSWorkspace.shared.open(url)
        case .blocked:
            break
        }
    }
}
