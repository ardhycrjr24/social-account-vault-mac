import SwiftUI
import SwiftData
import AppKit
import Observation
import SocialAccountVaultCore

/// Memasang ModelContainer hanya bila tersedia; tanpa crash bila nil.
private struct OptionalModelContainer: ViewModifier {
    let container: ModelContainer?

    func body(content: Content) -> some View {
        if let container {
            content.modelContainer(container)
        } else {
            content
        }
    }
}

/// Application entry point for Social Account Vault (Native macOS).
@main
struct SocialAccountVaultApp: App {
    /// Satu sumber kebenaran status storage untuk seluruh aplikasi.
    /// Bootstrap dilakukan SEBELUM view dipasang: kegagalan tidak crash dan
    /// tidak pernah mengganti database produksi dengan in-memory secara diam-diam.
    @State private var storage: StorageCoordinator
    @State private var domainRegistry: DomainRegistry

    init() {
        let coordinator = StorageCoordinator()
        coordinator.bootstrap()
        // Pastikan container selalu tersedia untuk SwiftUI (non-optional).
        // Saat FAILED ini adalah container diagnostik eksplisit yang TIDAK
        // dipakai untuk menyimpan data (semua tulis diblokir service).
        coordinator.prepareContainerForPresentation()

        // Registry produksi berasal dari resource JSON — bukan specificationExamples.
        // Kegagalan load menghasilkan registry kosong + diagnostic generik.
        let loadResult = DomainRegistryLoader.load()
        if let diagnostic = loadResult.diagnostic {
            NSLog("[SocialAccountVault] Domain registry: %@", diagnostic)
        }
        _domainRegistry = State(initialValue: loadResult.registry)
        _storage = State(initialValue: coordinator)
    }

    var body: some Scene {
        WindowGroup {
            MainNavigationView()
                .frame(minWidth: 960, minHeight: 600)
                .environment(storage)
                .environment(\.domainRegistry, domainRegistry)
                // Container produksi dipasang hanya saat READY. Saat FAILED,
                // container diagnostik EKSPLISIT dipakai agar UI tidak crash;
                // seluruh tulis tetap diblokir oleh StorageCoordinator.
                .modifier(OptionalModelContainer(container: storage.presentedContainer))
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1100, height: 720)
        .commands {
            SidebarCommands()
            ToolbarCommands()

            CommandGroup(replacing: .help) {
                // Link bantuan juga melewati validator; tidak ada jalur
                // NSWorkspace.shared.open yang langsung dari string.
                Button("Social Account Vault Help") {
                    helpURL = URLSafetyValidator().classify(
                        "https://github.com/ardhycrjr24/SocialAccountVault"
                    )
                }
                .confirmationDialog(
                    "Periksa tautan bantuan",
                    isPresented: Binding(
                        get: { helpURL != nil },
                        set: { if !$0 { helpURL = nil } }
                    )
                ) {
                    Button("Batal", role: .cancel) { helpURL = nil }
                    Button("Buka", role: .destructive) {
                        if let decision = helpURL, decision.isOpenable {
                            if case .safeToOpen(let url, _) = decision { NSWorkspace.shared.open(url) }
                            if case .warning(let url, _, _) = decision { NSWorkspace.shared.open(url) }
                        }
                        helpURL = nil
                    }
                } message: {
                    Text("Hostname: \(helpURL?.hostname ?? "-"). \(helpURL?.reasons.joined(separator: " ") ?? "")")
                }
            }
        }
    }

    @State private var helpURL: URLSafetyDecision?
}
