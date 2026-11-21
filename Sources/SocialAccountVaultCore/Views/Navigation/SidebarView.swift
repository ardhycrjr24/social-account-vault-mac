import SwiftUI
import SwiftData

/// Native macOS sidebar view presenting organized navigation categories.
public struct SidebarView: View {
    @Binding public var selectedItem: NavigationItem?

    @Query(filter: #Predicate<Account> { !$0.isArchived })
    private var activeAccounts: [Account]

    @Query(filter: #Predicate<Account> { $0.isArchived })
    private var archivedAccounts: [Account]

    public init(selectedItem: Binding<NavigationItem?>) {
        self._selectedItem = selectedItem
    }

    public var body: some View {
        List(selection: $selectedItem) {
            Section("Overview") {
                sidebarRow(for: .dashboard, badgeCount: nil)
                sidebarRow(for: .allAccounts, badgeCount: activeAccounts.count)
            }

            Section("Platforms") {
                sidebarRow(for: .youtube, badgeCount: count(for: [.youtube]))
                sidebarRow(for: .instagram, badgeCount: count(for: [.instagram]))
                sidebarRow(for: .tiktok, badgeCount: count(for: [.tiktok]))
                sidebarRow(for: .facebook, badgeCount: count(for: [.facebook]))
                sidebarRow(for: .email, badgeCount: count(for: [.email]))
                sidebarRow(for: .affiliateMonetization, badgeCount: count(for: [.shopeeAffiliate, .googleAdSense]))
                sidebarRow(for: .websiteDomain, badgeCount: count(for: [.websiteDomain]))
            }

            Section("Vault") {
                sidebarRow(for: .archive, badgeCount: archivedAccounts.count > 0 ? archivedAccounts.count : nil)
                sidebarRow(for: .settings, badgeCount: nil)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Social Vault")
    }

    @ViewBuilder
    private func sidebarRow(for item: NavigationItem, badgeCount: Int?) -> some View {
        NavigationLink(value: item) {
            HStack(spacing: 8) {
                Image(systemName: item.iconName)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(iconColor(for: item))
                    .frame(width: 20, alignment: .center)

                Text(item.rawValue)
                    .font(.system(.body, design: .default, weight: selectedItem == item ? .semibold : .regular))

                Spacer()

                if let count = badgeCount, count > 0 {
                    Text("\(count)")
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.18)))
                        .foregroundColor(.secondary)
                }
            }
            .frame(minHeight: 26)
        }
    }

    private func count(for platforms: [PlatformType]) -> Int {
        let platformNames = Set(platforms.map { $0.rawValue })
        return activeAccounts.filter { platformNames.contains($0.platform) }.count
    }

    private func iconColor(for item: NavigationItem) -> Color {
        switch item {
        case .dashboard:
            return .blue
        case .allAccounts:
            return .indigo
        case .youtube:
            return .red
        case .instagram:
            return .pink
        case .tiktok:
            return .cyan
        case .facebook:
            return .blue
        case .email:
            return .orange
        case .affiliateMonetization:
            return .green
        case .websiteDomain:
            return .teal
        case .archive:
            return .secondary
        case .settings:
            return .gray
        }
    }
}
