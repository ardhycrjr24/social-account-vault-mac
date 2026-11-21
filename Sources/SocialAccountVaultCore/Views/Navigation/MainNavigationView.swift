import SwiftUI
import SwiftData

/// Root navigation view coordinating the two-column sidebar split view and content routing.
public struct MainNavigationView: View {
    @State private var viewModel = NavigationViewModel()
    @State private var isShowingNewAccountSheet = false
    @Environment(\.modelContext) private var modelContext
    @Environment(StorageCoordinator.self) private var storage
    @State private var seedingErrorMessage: String?

    public init() {}

    public var body: some View {
        NavigationSplitView {
            SidebarView(selectedItem: $viewModel.selectedItem)
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 320)
        } detail: {
            Group {
                // Banner non-dismissible saat penyimpanan tidak tersedia.
                if !storage.status.isWritable {
                    storageFailureBanner
                }
                contentForSelection
            }
            .navigationTitle(viewModel.selectedItem?.rawValue ?? "Dashboard")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingNewAccountSheet = true
                    } label: {
                        Label("New Account", systemImage: "plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    .help("Register a new digital account in the vault (⌘N)")
                    .disabled(!storage.status.isWritable)
                }
            }
            .sheet(isPresented: $isShowingNewAccountSheet) {
                AddAccountView(initialPlatform: currentPlatformContext)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(
            text: $viewModel.searchText,
            placement: .toolbar,
            prompt: "Search accounts, usernames, emails..."
        )
        .preferredColorScheme(.dark)
        .onAppear {
            performInitialSeeding()
        }
    }

    public var currentPlatformContext: PlatformType {
        Self.defaultPlatform(for: viewModel.selectedItem)
    }

    public static func defaultPlatform(for item: NavigationItem?) -> PlatformType {
        guard let item = item else { return .youtube }
        return item.targetPlatformTypes.first ?? .youtube
    }

    private var storageFailureBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Penyimpanan tidak tersedia", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text(storage.status.userFacingMessage ?? "Data belum dapat disimpan.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if case .failed = storage.status {
                Button {
                    storage.retry()
                } label: {
                    Label("Coba Lagi", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
    }

    private func performInitialSeeding() {
        guard storage.status.isWritable else { return }
        do {
            _ = try CategorySeeder.seedDefaultCategoriesIfNeeded(modelContext: modelContext)
        } catch {
            seedingErrorMessage = error.localizedDescription
            print("[MainNavigationView] Error initializing default categories: \(error.localizedDescription)")
        }
    }

    @ViewBuilder
    private var contentForSelection: some View {
        switch viewModel.selectedItem ?? .dashboard {
        case .dashboard:
            DashboardPlaceholderView { destination in
                viewModel.selectedItem = destination
            }

        case .allAccounts:
            AccountsPlaceholderView(
                filterTitle: "All Accounts",
                targetPlatforms: [],
                searchText: viewModel.searchText
            )

        case .youtube:
            AccountsPlaceholderView(
                filterTitle: "YouTube",
                targetPlatforms: [.youtube],
                searchText: viewModel.searchText
            )

        case .instagram:
            AccountsPlaceholderView(
                filterTitle: "Instagram",
                targetPlatforms: [.instagram],
                searchText: viewModel.searchText
            )

        case .tiktok:
            AccountsPlaceholderView(
                filterTitle: "TikTok",
                targetPlatforms: [.tiktok],
                searchText: viewModel.searchText
            )

        case .facebook:
            AccountsPlaceholderView(
                filterTitle: "Facebook",
                targetPlatforms: [.facebook],
                searchText: viewModel.searchText
            )

        case .email:
            AccountsPlaceholderView(
                filterTitle: "Email",
                targetPlatforms: [.email],
                searchText: viewModel.searchText
            )

        case .affiliateMonetization:
            AccountsPlaceholderView(
                filterTitle: "Affiliate & Monetization",
                targetPlatforms: [.shopeeAffiliate, .googleAdSense],
                searchText: viewModel.searchText
            )

        case .websiteDomain:
            AccountsPlaceholderView(
                filterTitle: "Website & Domain",
                targetPlatforms: [.websiteDomain],
                searchText: viewModel.searchText
            )

        case .archive:
            ArchivePlaceholderView()

        case .settings:
            SettingsPlaceholderView()
        }
    }
}
