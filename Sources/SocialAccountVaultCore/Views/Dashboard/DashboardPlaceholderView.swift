import SwiftUI
import SwiftData

/// Professional Dashboard view summarizing account metrics, platform distribution,
/// recent accounts, audit stream, and domain reminders.
///
/// Designed with native macOS ergonomics: information-dense, interactive routing,
/// semantic hierarchy, and clean typography.
public struct DashboardPlaceholderView: View {
    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.updatedAt, order: .reverse)
    private var activeAccounts: [Account]

    @Query(filter: #Predicate<Account> { $0.isArchived })
    private var archivedAccounts: [Account]

    @Query(sort: \ActivityLog.timestamp, order: .reverse)
    private var recentActivityLogs: [ActivityLog]

    @Environment(StorageCoordinator.self) private var storage

    public var onNavigate: ((NavigationItem) -> Void)?

    @State private var selectedAccountForDetail: Account?
    @State private var hoveredKPIIndex: Int? = nil

    public init(onNavigate: ((NavigationItem) -> Void)? = nil) {
        self.onNavigate = onNavigate
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // 1. Dashboard Header
                dashboardHeader

                // 2. Unified KPI Summary Bar
                kpiSummaryBar

                // 3. Two-Column Modular Layout (Main Overview + Side Stream)
                HStack(alignment: .top, spacing: 20) {
                    // Left Column (60% weight): Recent Accounts & Platform Breakdown
                    VStack(alignment: .leading, spacing: 20) {
                        recentAccountsSection
                        platformBreakdownSection
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Right Column (40% weight): Activity Stream & Domain / Security Status
                    VStack(alignment: .leading, spacing: 20) {
                        recentActivitySection
                        domainStatusCard
                        securityStatusCard
                    }
                    .frame(width: 320)
                }
            }
            .padding(24)
        }
        .sheet(item: $selectedAccountForDetail) { account in
            AccountDetailView(account: account)
        }
    }

    // MARK: - 1. Dashboard Header

    @ViewBuilder
    private var dashboardHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Vault Dashboard")
                    .font(.title2.weight(.bold))

                Text("Operational security, verified brand presence, and access overview.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Header Status Pill — mengikuti StorageCoordinator (satu sumber kebenaran).
            HStack(spacing: 8) {
                Circle()
                    .fill(storageStatusColor)
                    .frame(width: 8, height: 8)

                Text(storageStatusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                Capsule()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )
        }
    }

    // MARK: - 2. Unified KPI Summary Bar

    @ViewBuilder
    private var kpiSummaryBar: some View {
        HStack(spacing: 0) {
            kpiSegment(
                index: 0,
                title: "Total Accounts",
                value: "\(activeAccounts.count + archivedAccounts.count)",
                subtitle: "\(activeAccounts.count) aktif · \(archivedAccounts.count) archived",
                icon: "person.2.fill",
                accentColor: .blue,
                destination: .allAccounts
            )

            Divider()
                .frame(height: 48)

            kpiSegment(
                index: 1,
                title: "Active Status",
                value: "\(activeCount)",
                subtitle: "\(activePercentage)% healthy",
                icon: "checkmark.circle.fill",
                accentColor: .green,
                destination: .allAccounts
            )

            Divider()
                .frame(height: 48)

            kpiSegment(
                index: 2,
                title: "Pending / Review",
                value: "\(pendingCount)",
                subtitle: pendingCount > 0 ? "Requires review" : "None pending",
                icon: "clock.fill",
                accentColor: pendingCount > 0 ? .orange : .secondary,
                destination: .allAccounts
            )

            Divider()
                .frame(height: 48)

            kpiSegment(
                index: 3,
                title: "Monetized",
                value: "\(monetizedCount)",
                subtitle: "Revenue enabled",
                icon: "dollarsign.circle.fill",
                accentColor: .yellow,
                destination: .affiliateMonetization
            )
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func kpiSegment(
        index: Int,
        title: String,
        value: String,
        subtitle: String,
        icon: String,
        accentColor: Color,
        destination: NavigationItem
    ) -> some View {
        Button {
            onNavigate?(destination)
        } label: {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(accentColor)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title.uppercased())
                        .font(.system(.caption2, design: .default, weight: .bold))
                        .foregroundColor(.secondary)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(value)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)

                        Text(subtitle)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(hoveredKPIIndex == index ? 0.08 : 0))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            hoveredKPIIndex = isHovered ? index : nil
        }
    }

    // MARK: - 3. Recent Accounts Section

    @ViewBuilder
    private var recentAccountsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recently Updated Accounts")
                    .font(.headline)

                Spacer()

                Button {
                    onNavigate?(.allAccounts)
                } label: {
                    HStack(spacing: 4) {
                        Text("View All")
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .font(.caption.weight(.medium))
                }
                .buttonStyle(.borderless)
            }

            if activeAccounts.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No registered accounts yet")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Click '+' in the top toolbar to register your first digital account.")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                    .padding(.vertical, 24)
                    Spacer()
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(activeAccounts.prefix(5).enumerated()), id: \.element.id) { index, account in
                        Button {
                            selectedAccountForDetail = account
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: iconFor(platform: account.platform))
                                    .font(.system(size: 14))
                                    .foregroundColor(.blue)
                                    .frame(width: 20)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.name)
                                        .font(.body.weight(.medium))
                                        .foregroundColor(.primary)

                                    HStack(spacing: 6) {
                                        Text(account.platform)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)

                                        if !account.username.isEmpty {
                                            Text("•")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            Text("@\(account.username)")
                                                .font(.system(.caption2, design: .monospaced))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }

                                Spacer()

                                expirationIndicator(for: account)

                                statusBadge(for: account.accountStatus)

                                Text(formattedDate(account.updatedAt))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .frame(width: 75, alignment: .trailing)

                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(.secondary.opacity(0.4))
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if index < min(activeAccounts.count, 5) - 1 {
                            Divider()
                                .padding(.horizontal, 14)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - 4. Platform Breakdown Section

    @ViewBuilder
    private var platformBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Platform Breakdown")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                ForEach(PlatformType.allCases) { platform in
                    platformItemRow(platform: platform)
                }
            }
        }
    }

    @ViewBuilder
    private func platformItemRow(platform: PlatformType) -> some View {
        let count = activeAccounts.filter { $0.platform == platform.rawValue }.count
        let navDestination = navigationItem(for: platform)

        Button {
            onNavigate?(navDestination)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: platform.iconName)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(platformColor(for: platform))
                    .frame(width: 22, height: 22)
                    .background(platformColor(for: platform).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text(platform.rawValue)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)

                Spacer()

                Text("\(count)")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundColor(count > 0 ? .primary : .secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(count > 0 ? Color.secondary.opacity(0.18) : Color.clear)
                    )

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.4))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 5. Recent Activity Feed (Audit Stream)

    @ViewBuilder
    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent Activity")
                    .font(.headline)
                Spacer()
                Image(systemName: "waveform.path.ecg")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if recentActivityLogs.isEmpty {
                VStack(spacing: 6) {
                    Text("No activity recorded")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Account events and status checks will stream here.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentActivityLogs.prefix(5).enumerated()), id: \.element.id) { index, log in
                        HStack(alignment: .top, spacing: 10) {
                            actionIcon(for: log.actionType)
                                .frame(width: 16)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(log.actionType)
                                        .font(.caption.weight(.semibold))

                                    Spacer()

                                    Text(formattedRelativeTime(log.timestamp))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                if let targetAccount = log.account {
                                    Button {
                                        selectedAccountForDetail = targetAccount
                                    } label: {
                                        Text(targetAccount.name)
                                            .font(.caption2.weight(.medium))
                                            .foregroundColor(.blue)
                                            .underline()
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    // Details sengaja tidak ditampilkan: dapat berisi
                                    // teks bebas pengguna dan berpotensi sensitif.
                                    Text("Aktivitas tercatat")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)

                        if index < min(recentActivityLogs.count, 5) - 1 {
                            Divider()
                                .padding(.horizontal, 12)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - 6. Domain Status Card

    @ViewBuilder
    private var domainStatusCard: some View {
        let reminders = expirationReminders

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "globe")
                    .foregroundColor(.teal)
                Text("Domain Expiration")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(reminders.count) reminder")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if reminders.isEmpty {
                Text("Tidak ada domain yang akan kedaluwarsa dalam 90 hari.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                ForEach(reminders, id: \.id) { item in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: item.badge.iconName)
                            .foregroundColor(reminderColor(item.badge))
                            .font(.caption2)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name)
                                .font(.caption.weight(.medium))
                            Text("\(item.badge.displayText ?? "") · \(formattedDate(item.date))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private struct ExpirationReminder: Identifiable {
        let id = UUID()
        let name: String
        let date: Date
        let badge: ExpirationBadge
    }

    private var expirationReminders: [ExpirationReminder] {
        let lifecycle = AccountLifecycle()
        return activeAccounts.compactMap { account in
            let badge = lifecycle.expirationBadge(
                for: account.domainExpirationDate,
                isArchived: account.isArchived
            )
            guard badge != .none, let date = account.domainExpirationDate else { return nil }
            return ExpirationReminder(name: account.name, date: date, badge: badge)
        }
        .sorted { $0.date < $1.date }
    }

    private func reminderColor(_ badge: ExpirationBadge) -> Color {
        switch badge {
        case .expired, .within30: return .red
        case .within60: return .orange
        case .within90: return .yellow
        case .none: return .secondary
        }
    }

    private var storageStatusColor: Color {
        switch storage.status {
        case .ready: return .green
        case .failed: return .red
        case .recovering: return .orange
        }
    }

    private var storageStatusText: String {
        switch storage.status {
        case .ready: return "Penyimpanan siap"
        case .failed: return "Penyimpanan gagal — data belum tersimpan"
        case .recovering: return "Penyimpanan sedang dipulihkan"
        }
    }

    // MARK: - 7. Security Status Card

    @ViewBuilder
    private var securityStatusCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.title2)
                .foregroundColor(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text("Zero-Credential Vault")
                    .font(.caption.weight(.bold))
                Text("Zero passwords, tokens, or private secrets stored. 100% offline.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.green.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.green.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Helper Methods

    private var activeCount: Int {
        activeAccounts.filter { $0.accountStatus == .active }.count
    }

    private var pendingCount: Int {
        activeAccounts.filter { $0.accountStatus == .pending }.count
    }

    private var monetizedCount: Int {
        activeAccounts.filter { $0.monetizationStatus == .monetized }.count
    }

    private var activePercentage: Int {
        guard !activeAccounts.isEmpty else { return 100 }
        return Int((Double(activeCount) / Double(activeAccounts.count)) * 100)
    }

    private func navigationItem(for platform: PlatformType) -> NavigationItem {
        switch platform {
        case .youtube: return .youtube
        case .instagram: return .instagram
        case .tiktok: return .tiktok
        case .facebook: return .facebook
        case .email: return .email
        case .shopeeAffiliate, .googleAdSense: return .affiliateMonetization
        case .websiteDomain: return .websiteDomain
        }
    }

    private func platformColor(for platform: PlatformType) -> Color {
        switch platform {
        case .youtube: return .red
        case .instagram: return .pink
        case .tiktok: return .cyan
        case .facebook: return .blue
        case .email: return .orange
        case .shopeeAffiliate: return .green
        case .googleAdSense: return .yellow
        case .websiteDomain: return .teal
        }
    }

    private func iconFor(platform: String) -> String {
        PlatformType(rawValue: platform)?.iconName ?? "globe"
    }

    @ViewBuilder
    private func statusBadge(for status: AccountStatus) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(status == .active ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            Text(status.rawValue)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func actionIcon(for actionType: String) -> some View {
        switch actionType {
        case "Created":
            Image(systemName: "plus.circle.fill").font(.caption).foregroundColor(.blue)
        case "Updated":
            Image(systemName: "pencil.circle.fill").font(.caption).foregroundColor(.orange)
        case "Archived":
            Image(systemName: "archivebox.fill").font(.caption).foregroundColor(.secondary)
        case "Restored":
            Image(systemName: "arrow.uturn.backward.circle.fill").font(.caption).foregroundColor(.green)
        case "Status Checked":
            Image(systemName: "checkmark.seal.fill").font(.caption).foregroundColor(.teal)
        default:
            Image(systemName: "circle.fill").font(.caption2).foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func expirationIndicator(for account: Account) -> some View {
        let badge = AccountLifecycle().expirationBadge(
            for: account.domainExpirationDate,
            isArchived: account.isArchived
        )
        if let text = badge.displayText {
            Label(text, systemImage: badge.iconName)
                .font(.caption2)
                .foregroundColor(badge == .expired || badge == .within30 ? .red : .orange)
                .lineLimit(1)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func formattedRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
