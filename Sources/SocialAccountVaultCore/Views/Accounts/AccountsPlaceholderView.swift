import SwiftUI
import SwiftData
import AppKit

/// View displaying account listings filtered by platform category or search queries.
///
/// Features minimalist column layout, single More Actions menu per row,
/// clean solid backgrounds without zebra stripes, row selection, double-click to view details,
/// and complete contextual actions (View Details, Edit, Open Links, Archive, Delete with confirmation).
public struct AccountsPlaceholderView: View {
    public let filterTitle: String
    public let targetPlatforms: [PlatformType]
    public let searchText: String

    @Environment(\.modelContext) private var modelContext
    @Environment(StorageCoordinator.self) private var storage
    @Environment(\.domainRegistry) private var domainRegistry

    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.name)
    private var allActiveAccounts: [Account]

    // Selection & Presentation State
    @State private var selectedAccountID: UUID?
    @State private var accountForDetail: Account?
    @State private var accountForEdit: Account?
    @State private var accountForDelete: Account?
    @State private var isShowingDeleteConfirmation: Bool = false
    @State private var errorMessage: String?
    @State private var isShowingErrorAlert: Bool = false

    public init(
        filterTitle: String,
        targetPlatforms: [PlatformType],
        searchText: String = ""
    ) {
        self.filterTitle = filterTitle
        self.targetPlatforms = targetPlatforms
        self.searchText = searchText
    }

    public var filteredAccounts: [Account] {
        var result = allActiveAccounts

        // Apply platform filter if specified
        if !targetPlatforms.isEmpty {
            let names = Set(targetPlatforms.map { $0.rawValue })
            result = result.filter { names.contains($0.platform) }
        }

        // Apply search query if specified
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            result = result.filter { account in
                account.name.localizedCaseInsensitiveContains(trimmed) ||
                account.username.localizedCaseInsensitiveContains(trimmed) ||
                account.emailReference.localizedCaseInsensitiveContains(trimmed) ||
                account.platform.localizedCaseInsensitiveContains(trimmed)
            }
        }

        return result
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(filterTitle)
                        .font(.title2.weight(.bold))
                    Text("\(filteredAccounts.count) active account\(filteredAccounts.count == 1 ? "" : "s") registered")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let selectedID = selectedAccountID,
                   let selected = filteredAccounts.first(where: { $0.id == selectedID }) {
                    Button {
                        accountForDetail = selected
                    } label: {
                        Label("View Details", systemImage: "info.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            if filteredAccounts.isEmpty {
                emptyStateView
            } else {
                accountsTable
            }
        }
        .sheet(item: $accountForDetail) { account in
            AccountDetailView(account: account)
        }
        .sheet(item: $accountForEdit) { account in
            AddAccountView(editing: account)
        }
        .confirmationDialog(
            "Delete Account '\(accountForDelete?.name ?? "")'?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) {
                if let account = accountForDelete {
                    performDelete(account)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove this account, its metadata, and all related audit history from this device. Consider archiving instead if you wish to retain audit history. This action cannot be undone.")
        }
        .alert("Error", isPresented: $isShowingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unexpected error occurred.")
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: targetPlatforms.first?.iconName ?? "person.crop.circle.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.6))

            VStack(spacing: 6) {
                Text("No Accounts Registered")
                    .font(.headline)
                Text(targetPlatforms.isEmpty
                    ? "Add your digital accounts to begin managing your online presence securely."
                    : "No accounts found for \(filterTitle). Click '+' to register an account."
                )
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var accountsTable: some View {
        Table(filteredAccounts, selection: $selectedAccountID) {
            TableColumn("Account Name") { account in
                HStack(spacing: 8) {
                    Image(systemName: iconFor(platform: account.platform))
                        .foregroundColor(.blue)
                        .frame(width: 18)
                    Text(account.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    accountForDetail = account
                }
                .contextMenu {
                    accountActionsMenu(for: account)
                }
            }
            .width(min: 160, ideal: 240, max: 360)

            TableColumn("Platform") { account in
                Text(account.platform)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        accountForDetail = account
                    }
                    .contextMenu {
                        accountActionsMenu(for: account)
                    }
            }
            .width(min: 90, ideal: 120, max: 140)

            TableColumn("Username") { account in
                Text(account.username.isEmpty ? "—" : "@\(account.username)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(account.username.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        accountForDetail = account
                    }
                    .contextMenu {
                        accountActionsMenu(for: account)
                    }
            }
            .width(min: 100, ideal: 150, max: 200)

            TableColumn("Status") { account in
                statusBadge(for: account.accountStatus)
                    .contextMenu {
                        accountActionsMenu(for: account)
                    }
            }
            .width(min: 80, ideal: 95, max: 110)

            TableColumn("Expiration") { account in
                expirationText(for: account)
                    .foregroundColor(expirationColor(for: account))
                    .lineLimit(1)
                    .contextMenu {
                        accountActionsMenu(for: account)
                    }
            }
            .width(min: 90, ideal: 130, max: 150)

            TableColumn("Monetization") { account in
                monetizationBadge(for: account.monetizationStatus)
                    .contextMenu {
                        accountActionsMenu(for: account)
                    }
            }
            .width(min: 95, ideal: 115, max: 130)

            TableColumn("Actions") { account in
                Menu {
                    accountActionsMenu(for: account)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 22, height: 22)
                .help("More Actions")
            }
            .width(min: 44, ideal: 50, max: 60)
        }
        // Eliminates artificial alternating grey rows across empty viewport on macOS
        .tableStyle(.inset(alternatesRowBackgrounds: false))
    }

    @ViewBuilder
    private func accountActionsMenu(for account: Account) -> some View {
        Button {
            accountForDetail = account
        } label: {
            Label("View Details", systemImage: "info.circle")
        }

        Button {
            accountForEdit = account
        } label: {
            Label("Edit Account...", systemImage: "pencil")
        }

        SafeLinkButton(
            title: "Open Profile in Browser",
            urlString: account.profileURLString,
            platform: account.platform,
            registry: domainRegistry
        )

        SafeLinkButton(
            title: "Open Creator Dashboard",
            urlString: account.officialDashboardURLString,
            platform: account.platform,
            registry: domainRegistry,
            systemImage: "chart.bar.doc.horizontal"
        )

        Divider()

        Button {
            performArchive(account)
        } label: {
            Label("Archive Account", systemImage: "archivebox")
        }

        Button(role: .destructive) {
            accountForDelete = account
            isShowingDeleteConfirmation = true
        } label: {
            Label("Delete Account...", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func statusBadge(for status: AccountStatus) -> some View {
        HStack(spacing: 4) {
            Image(systemName: status.iconName)
                .font(.caption2)
            Text(status.rawValue)
                .font(.caption)
        }
        .foregroundColor(status == .active ? .green : .secondary)
    }

    @ViewBuilder
    private func monetizationBadge(for status: MonetizationStatus) -> some View {
        HStack(spacing: 4) {
            Image(systemName: status.iconName)
                .font(.caption2)
            Text(status.rawValue)
                .font(.caption)
        }
        .foregroundColor(status == .monetized ? .yellow : .secondary)
    }

    private func expirationBadge(for account: Account) -> ExpirationBadge {
        AccountLifecycle().expirationBadge(
            for: account.domainExpirationDate,
            isArchived: account.isArchived
        )
    }

    private func expirationText(for account: Account) -> Text {
        Text(expirationBadge(for: account).displayText ?? "—")
    }

    private func expirationColor(for account: Account) -> Color {
        switch expirationBadge(for: account) {
        case .expired, .within30: return .red
        case .within60, .within90: return .orange
        case .none: return .secondary
        }
    }

    private func iconFor(platform: String) -> String {
        PlatformType(rawValue: platform)?.iconName ?? "globe"
    }

    private func performArchive(_ account: Account) {
        let service = VaultDataService(modelContext: modelContext, storageGate: storage)
        do {
            try service.archiveAccount(account)
        } catch {
            errorMessage = error.localizedDescription
            isShowingErrorAlert = true
        }
    }

    private func performDelete(_ account: Account) {
        let service = VaultDataService(modelContext: modelContext, storageGate: storage)
        do {
            try service.deleteAccount(account)
        } catch {
            errorMessage = error.localizedDescription
            isShowingErrorAlert = true
        }
    }
}
