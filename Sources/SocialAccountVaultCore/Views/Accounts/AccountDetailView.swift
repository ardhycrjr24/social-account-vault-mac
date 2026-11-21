import SwiftUI
import SwiftData
import AppKit

/// Comprehensive detail view displaying account metadata, links, audit logs, and actions.
///
/// Security Invariant:
/// Never displays or requests passwords, OTPs, recovery codes, or private credentials.
@MainActor
public struct AccountDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(StorageCoordinator.self) private var storage
    @Environment(\.domainRegistry) private var domainRegistry

    @Bindable public var account: Account

    // State for Modals & Dialogs
    @State private var isShowingEditSheet: Bool = false
    @State private var isShowingDetailEditor: Bool = false
    @State private var isShowingDeleteConfirmation: Bool = false
    @State private var isShowingAddDetailSheet: Bool = false
    @State private var newDetailKey: String = ""
    @State private var newDetailValue: String = ""
    @State private var errorMessage: String?
    @State private var isShowingErrorAlert: Bool = false

    public init(account: Account) {
        self.account = account
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header Card
                    headerSection

                    // Quick URL Actions
                    if account.hasValidProfileURL || account.hasValidOfficialDashboardURL
                        || !account.directLoginURLString.isEmpty {
                        webLinksSection
                    }

                    // Key-Value Metadata Section
                    metadataSection

                    // Operational Notes Section
                    if !account.notes.isEmpty {
                        notesSection
                    }

                    // Activity History / Audit Log Section
                    activityLogSection
                }
                .padding(24)
            }
            .navigationTitle(account.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        isShowingEditSheet = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .help("Edit account information")
                    .disabled(!storage.status.isWritable)

                    Button {
                        isShowingDetailEditor = true
                    } label: {
                        Label("Detail", systemImage: "slider.horizontal.3")
                    }
                    .help("Edit recovery, 2FA, device, login URL, and metadata")
                    .disabled(!storage.status.isWritable)

                    if account.isArchived {
                        Button {
                            restoreAccount()
                        } label: {
                            Label("Restore", systemImage: "arrow.uturn.backward.circle")
                        }
                        .help("Restore this account to the active vault")

                        Button(role: .destructive) {
                            isShowingDeleteConfirmation = true
                        } label: {
                            Label("Delete Permanently", systemImage: "trash")
                        }
                        .help("Permanently delete this account from vault")
                    } else {
                        Button {
                            archiveAccount()
                        } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                        .help("Move this account to the archive")

                        Button(role: .destructive) {
                            isShowingDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .help("Permanently delete this account from vault")
                    }
                }
            }
            .sheet(isPresented: $isShowingEditSheet) {
                AddAccountView(editing: account)
            }
            .sheet(isPresented: $isShowingDetailEditor) {
                AccountDetailEditorView(account: account)
            }
            .sheet(isPresented: $isShowingAddDetailSheet) {
                addDetailSheetView
            }
            .confirmationDialog(
                account.isArchived ? "Permanently Delete '\(account.name)'?" : "Delete Account '\(account.name)'?",
                isPresented: $isShowingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Permanently", role: .destructive) {
                    deleteAccount()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(account.isArchived
                    ? "This will permanently remove this account, its metadata, and all related audit logs from this device. This action cannot be undone."
                    : "This will permanently remove this account, its metadata, and all related audit history from this device. Consider archiving instead if you wish to retain audit history. This action cannot be undone."
                )
            }
            .alert("Error", isPresented: $isShowingErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An unexpected error occurred.")
            }
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 600, idealHeight: 700)
    }

    // MARK: - Sections

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                Image(systemName: iconFor(platform: account.platform))
                    .font(.system(size: 36))
                    .foregroundColor(.accentColor)
                    .frame(width: 54, height: 54)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(account.name)
                        .font(.title2.weight(.bold))

                    HStack(spacing: 8) {
                        Text(account.platform)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)

                        if !account.username.isEmpty {
                            Text("•")
                                .foregroundColor(.secondary)
                            Text("@\(account.username)")
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundColor(.secondary)
                        }

                        if !account.emailReference.isEmpty {
                            Text("•")
                                .foregroundColor(.secondary)
                            Text(account.emailReference)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                Button {
                    markChecked()
                } label: {
                    Label("Check Status", systemImage: "checkmark.seal")
                }
                .buttonStyle(.bordered)
                .disabled(!storage.status.isWritable)
                .help("Record a manual verification check in the audit log")
            }

            // Badges Row
            HStack(spacing: 10) {
                badgePill(
                    icon: account.accountType.iconName,
                    text: account.accountType.rawValue,
                    color: .blue
                )

                badgePill(
                    icon: account.accountStatus.iconName,
                    text: account.accountStatus.rawValue,
                    color: account.accountStatus == .active ? .green : .orange
                )

                badgePill(
                    icon: account.monetizationStatus.iconName,
                    text: account.monetizationStatus.rawValue,
                    color: account.monetizationStatus == .monetized ? .purple : .secondary
                )

                if account.isArchived {
                    badgePill(
                        icon: "archivebox.fill",
                        text: "Archived",
                        color: .secondary
                    )
                }

                if let badge = expirationBadge, let expDate = account.domainExpirationDate {
                    badgePill(
                        icon: badge.iconName,
                        text: "\(badge.displayText ?? "Exp") · \(formattedDate(expDate))",
                        color: badgeColor(badge)
                    )
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    @ViewBuilder
    private var webLinksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Web & Dashboard Links")
                .font(.headline)

            HStack(spacing: 12) {
                SafeLinkButton(
                    title: "Public Profile",
                    urlString: account.profileURLString,
                    platform: account.platform,
                    registry: domainRegistry,
                    prominent: true
                )

                SafeLinkButton(
                    title: "Creator Dashboard",
                    urlString: account.officialDashboardURLString,
                    platform: account.platform,
                    registry: domainRegistry,
                    systemImage: "chart.bar.doc.horizontal"
                )

                if !account.directLoginURLString.isEmpty {
                    SafeLinkButton(
                        title: "Direct Login",
                        urlString: account.directLoginURLString,
                        platform: account.platform,
                        registry: domainRegistry,
                        systemImage: "lock.rectangle"
                    )
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    @ViewBuilder
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Operational Metadata")
                    .font(.headline)
                Spacer()
                Button {
                    newDetailKey = ""
                    newDetailValue = ""
                    isShowingAddDetailSheet = true
                } label: {
                    Label("Add Metadata", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            if account.details.isEmpty {
                Text("No operational metadata attributes registered. Click '+ Add Metadata' to store non-sensitive identifiers (e.g. Channel ID, Publisher ID).")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(account.details) { detail in
                        HStack {
                            Text(detail.key)
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 180, alignment: .leading)

                            Text(detail.value)
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundColor(.primary)

                            Spacer()

                            Button(role: .destructive) {
                                removeDetail(detail)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove this metadata item")
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    @ViewBuilder
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Operational Notes")
                .font(.headline)

            Text(account.notes)
                .font(.body)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    @ViewBuilder
    private var activityLogSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity & Audit History")
                .font(.headline)

            let logs = account.sortedActivityLogs
            if logs.isEmpty {
                Text("No activity logs recorded yet.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(logs.reversed()) { log in
                        HStack(alignment: .top, spacing: 12) {
                            Text("#\(log.sequenceNumber)")
                                .font(.system(.caption, design: .monospaced, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.secondary.opacity(0.15)))

                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(log.actionType)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(formattedTimestamp(log.timestamp))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                if !log.details.isEmpty {
                                    Text(log.details)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    // MARK: - Add Detail Sheet

    @ViewBuilder
    private var addDetailSheetView: some View {
        NavigationStack {
            Form {
                Section("Metadata Key & Value") {
                    TextField("Key (e.g. Channel ID, Nameserver)", text: $newDetailKey)
                        .textFieldStyle(.roundedBorder)

                    TextField("Value", text: $newDetailValue)
                        .textFieldStyle(.roundedBorder)
                }

                Section {
                    Text("Zero-Credential Guarantee: Never store passwords, tokens, recovery codes, or API secrets. Only non-sensitive operational identifiers are allowed.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Metadata")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        isShowingAddDetailSheet = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        saveNewDetail()
                    }
                    .disabled(newDetailKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 420, idealWidth: 460, minHeight: 260, idealHeight: 300)
    }

    // MARK: - Helper Methods

    private func badgePill(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption.weight(.medium))
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.12)))
    }

    private func iconFor(platform: String) -> String {
        PlatformType(rawValue: platform)?.iconName ?? "globe"
    }

    private var expirationBadge: ExpirationBadge? {
        let badge = AccountLifecycle().expirationBadge(
            for: account.domainExpirationDate,
            isArchived: account.isArchived
        )
        if case .none = badge { return nil }
        return badge
    }

    private func badgeColor(_ badge: ExpirationBadge) -> Color {
        switch badge {
        case .within90: return .yellow
        case .within60: return .orange
        case .within30, .expired: return .red
        case .none: return .secondary
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func formattedTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func markChecked() {
        let service = VaultDataService(modelContext: modelContext, storageGate: storage)
        do {
            try service.markChecked(account)
        } catch {
            errorMessage = error.localizedDescription
            isShowingErrorAlert = true
        }
    }

    private func archiveAccount() {
        let service = VaultDataService(modelContext: modelContext, storageGate: storage)
        do {
            try service.archiveAccount(account)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isShowingErrorAlert = true
        }
    }

    private func restoreAccount() {
        let service = VaultDataService(modelContext: modelContext, storageGate: storage)
        do {
            try service.restoreAccount(account)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isShowingErrorAlert = true
        }
    }

    private func deleteAccount() {
        let service = VaultDataService(modelContext: modelContext, storageGate: storage)
        do {
            try service.deleteAccount(account)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isShowingErrorAlert = true
        }
    }

    private func saveNewDetail() {
        let service = VaultDataService(modelContext: modelContext, storageGate: storage)
        do {
            try service.addDetail(to: account, key: newDetailKey, value: newDetailValue)
            isShowingAddDetailSheet = false
        } catch {
            errorMessage = error.localizedDescription
            isShowingErrorAlert = true
        }
    }

    private func removeDetail(_ detail: AccountDetail) {
        let service = VaultDataService(modelContext: modelContext, storageGate: storage)
        do {
            try service.removeDetail(detail)
        } catch {
            errorMessage = error.localizedDescription
            isShowingErrorAlert = true
        }
    }
}
