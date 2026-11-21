import SwiftUI
import SwiftData

/// View displaying archived accounts with options to restore or permanently remove.
public struct ArchivePlaceholderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(StorageCoordinator.self) private var storage

    @Query(filter: #Predicate<Account> { $0.isArchived }, sort: \Account.name)
    private var archivedAccounts: [Account]

    @State private var accountForDetail: Account?
    @State private var accountToDelete: Account?
    @State private var isShowingDeleteConfirmation: Bool = false
    @State private var errorMessage: String?
    @State private var isShowingErrorAlert: Bool = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Archived Accounts")
                        .font(.title2.weight(.bold))
                    Text("\(archivedAccounts.count) archived account\(archivedAccounts.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            if archivedAccounts.isEmpty {
                emptyStateView
            } else {
                archiveList
            }
        }
        .sheet(item: $accountForDetail) { account in
            AccountDetailView(account: account)
        }
        .confirmationDialog(
            "Permanently Delete '\(accountToDelete?.name ?? "")'?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) {
                if let account = accountToDelete {
                    performPermanentDelete(account)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove this account and its activity logs from this device. This action cannot be undone.")
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
            Image(systemName: "archivebox")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.6))
            Text("No Archived Accounts")
                .font(.headline)
            Text("Accounts that you archive will appear here safely out of view until restored.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var archiveList: some View {
        List(archivedAccounts) { account in
            HStack(spacing: 12) {
                Image(systemName: iconFor(platform: account.platform))
                    .foregroundColor(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name)
                        .font(.body.weight(.medium))

                    HStack(spacing: 6) {
                        Text(account.platform)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if !account.username.isEmpty {
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("@\(account.username)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                // Actions: Restore & Delete Permanently
                HStack(spacing: 10) {
                    Button {
                        accountForDetail = account
                    } label: {
                        Label("Details", systemImage: "info.circle")
                    }
                    .buttonStyle(.bordered)
                    .help("View account history and details")

                    Button {
                        performRestore(account)
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Restore this account to the active vault")
                    .disabled(!storage.status.isWritable)

                    Button(role: .destructive) {
                        accountToDelete = account
                        isShowingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("Permanently delete this account")
                    .disabled(!storage.status.isWritable)
                }
            }
            .padding(.vertical, 6)
            .contextMenu {
                Button {
                    accountForDetail = account
                } label: {
                    Label("View Details", systemImage: "info.circle")
                }

                Button {
                    performRestore(account)
                } label: {
                    Label("Restore Account", systemImage: "arrow.uturn.backward.circle")
                }

                Divider()

                Button(role: .destructive) {
                    accountToDelete = account
                    isShowingDeleteConfirmation = true
                } label: {
                    Label("Delete Permanently...", systemImage: "trash")
                }
            }
        }
        .listStyle(.inset)
    }

    private func iconFor(platform: String) -> String {
        PlatformType(rawValue: platform)?.iconName ?? "globe"
    }

    private func performRestore(_ account: Account) {
        let service = VaultDataService(modelContext: modelContext, storageGate: storage)
        do {
            try service.restoreAccount(account)
        } catch {
            errorMessage = error.localizedDescription
            isShowingErrorAlert = true
        }
    }

    private func performPermanentDelete(_ account: Account) {
        let service = VaultDataService(modelContext: modelContext, storageGate: storage)
        do {
            try service.deleteAccount(account)
        } catch {
            errorMessage = error.localizedDescription
            isShowingErrorAlert = true
        }
    }
}
