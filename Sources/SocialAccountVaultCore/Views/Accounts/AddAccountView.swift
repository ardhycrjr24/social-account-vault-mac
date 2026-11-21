import SwiftUI
import SwiftData

/// Modal form allowing users to create a new account or edit an existing account.
///
/// Security Invariant:
/// Under no circumstances does this view collect or store passwords, OTPs,
/// API keys, OAuth tokens, session cookies, or private credentials.
@MainActor
public struct AddAccountView: View {
    public enum FormMode: Equatable {
        case create(initialPlatform: PlatformType)
        case edit(accountID: UUID)

        public static func == (lhs: FormMode, rhs: FormMode) -> Bool {
            switch (lhs, rhs) {
            case (.create(let p1), .create(let p2)):
                return p1 == p2
            case (.edit(let id1), .edit(let id2)):
                return id1 == id2
            default:
                return false
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(StorageCoordinator.self) private var storage

    @Query(sort: \PlatformCategory.displayOrder)
    private var categories: [PlatformCategory]

    public let mode: FormMode
    public var accountToEdit: Account?

    // Form State
    @State private var name: String = ""
    @State private var selectedPlatform: PlatformType = .youtube
    @State private var username: String = ""
    @State private var emailReference: String = ""
    @State private var profileURLString: String = ""
    @State private var officialDashboardURLString: String = ""
    @State private var accountType: AccountType = .personal
    @State private var accountStatus: AccountStatus = .active
    @State private var monetizationStatus: MonetizationStatus = .notMonetized
    @State private var notes: String = ""

    // Domain Specific
    @State private var enableDomainExpiration: Bool = false
    @State private var domainExpirationDate: Date = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()

    // Error Presentation
    @State private var errorMessage: String?
    @State private var isShowingErrorAlert: Bool = false
    @State private var isSaving: Bool = false

    /// Initializer for creating a new account under a specific platform.
    public init(initialPlatform: PlatformType = .youtube) {
        self.mode = .create(initialPlatform: initialPlatform)
        self.accountToEdit = nil
        _selectedPlatform = State(initialValue: initialPlatform)
        _officialDashboardURLString = State(initialValue: initialPlatform.defaultDashboardURL)
        if initialPlatform == .websiteDomain {
            _enableDomainExpiration = State(initialValue: true)
        }
    }

    /// Initializer for editing an existing account.
    public init(editing account: Account) {
        self.mode = .edit(accountID: account.id)
        self.accountToEdit = account

        let platformEnum = PlatformType(rawValue: account.platform) ?? .youtube
        _selectedPlatform = State(initialValue: platformEnum)
        _name = State(initialValue: account.name)
        _username = State(initialValue: account.username)
        _emailReference = State(initialValue: account.emailReference)
        _profileURLString = State(initialValue: account.profileURLString)
        _officialDashboardURLString = State(initialValue: account.officialDashboardURLString)
        _accountType = State(initialValue: account.accountType)
        _accountStatus = State(initialValue: account.accountStatus)
        _monetizationStatus = State(initialValue: account.monetizationStatus)
        _notes = State(initialValue: account.notes)

        if let expDate = account.domainExpirationDate {
            _enableDomainExpiration = State(initialValue: true)
            _domainExpirationDate = State(initialValue: expDate)
        } else if platformEnum == .websiteDomain {
            _enableDomainExpiration = State(initialValue: true)
        }
    }

    public var isEditMode: Bool {
        if case .edit = mode {
            return true
        }
        return false
    }

    public var navigationTitleString: String {
        isEditMode ? "Edit Account" : "New Account"
    }

    public var saveButtonString: String {
        isEditMode ? "Save Changes" : "Save"
    }

    public var body: some View {
        NavigationStack {
            Form {
                // Section 1: Platform & Identity
                Section("Platform & Identity") {
                    Picker("Platform", selection: $selectedPlatform) {
                        ForEach(PlatformType.allCases) { platform in
                            Label(platform.rawValue, systemImage: platform.iconName)
                                .tag(platform)
                        }
                    }
                    .pickerStyle(.menu)

                    TextField("Account Name", text: $name, prompt: Text("e.g. Primary Tech Channel (Required)"))
                        .textFieldStyle(.roundedBorder)

                    TextField("Username / Handle", text: $username, prompt: Text("e.g. techpro (optional)"))
                        .textFieldStyle(.roundedBorder)
                }

                // Section 2: Contact & Online Presence
                Section("Contact & Web Presence") {
                    TextField("Email Reference", text: $emailReference, prompt: Text("e.g. contact@example.com (optional)"))
                        .textFieldStyle(.roundedBorder)

                    TextField("Public Profile URL", text: $profileURLString, prompt: Text("https://... (optional)"))
                        .textFieldStyle(.roundedBorder)

                    TextField("Official Dashboard URL", text: $officialDashboardURLString, prompt: Text("https://... (optional)"))
                        .textFieldStyle(.roundedBorder)
                }

                // Section 3: Classification & Status
                Section("Classification & Status") {
                    Picker("Account Type", selection: $accountType) {
                        ForEach(AccountType.allCases) { type in
                            Label(type.rawValue, systemImage: type.iconName)
                                .tag(type)
                        }
                    }

                    Picker("Operating Status", selection: $accountStatus) {
                        ForEach(AccountStatus.allCases) { status in
                            Label(status.rawValue, systemImage: status.iconName)
                                .tag(status)
                        }
                    }

                    Picker("Monetization", selection: $monetizationStatus) {
                        ForEach(MonetizationStatus.allCases) { mon in
                            Label(mon.rawValue, systemImage: mon.iconName)
                                .tag(mon)
                        }
                    }

                    if selectedPlatform == .websiteDomain {
                        Toggle("Track Domain Expiration", isOn: $enableDomainExpiration)

                        if enableDomainExpiration {
                            DatePicker("Expiration Date", selection: $domainExpirationDate, displayedComponents: [.date])
                        }
                    }
                }

                // Section 4: Operational Notes
                Section("Operational Notes") {
                    TextField(
                        "Operational Reminders / Context (Do not enter passwords or credentials)",
                        text: $notes,
                        axis: .vertical
                    )
                    .lineLimit(3...5)
                    .textFieldStyle(.roundedBorder)
                }

                // Section 5: Security Policy
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "shield.checkerboard")
                            .font(.title2)
                            .foregroundColor(.accentColor)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Zero-Credential Vault")
                                .font(.caption.weight(.bold))
                            Text("Social Account Vault stores only non-sensitive operational metadata. Passwords, OTPs, recovery codes, and tokens are never requested or persisted.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(navigationTitleString)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(saveButtonString) {
                        saveAccount()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving || !storage.status.isWritable)
                }
            }
            .alert("Cannot Save Account", isPresented: $isShowingErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An unknown validation error occurred.")
            }
            .onChange(of: selectedPlatform) { _, newPlatform in
                if !isEditMode {
                    let defaultURLs = PlatformType.allCases.map(\.defaultDashboardURL)
                    if officialDashboardURLString.isEmpty || defaultURLs.contains(officialDashboardURLString) {
                        officialDashboardURLString = newPlatform.defaultDashboardURL
                    }
                }
                if newPlatform == .websiteDomain && !enableDomainExpiration {
                    enableDomainExpiration = true
                }
            }
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 520, idealHeight: 580)
    }

    private func saveAccount() {
        guard !isSaving else { return }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Account Name cannot be empty."
            isShowingErrorAlert = true
            return
        }

        isSaving = true
        let service = VaultDataService(modelContext: modelContext, storageGate: storage)

        do {
            if isEditMode, let existingAccount = accountToEdit {
                // Update existing account in place (guarantees NO duplicate Account creation)
                try service.updateAccount(
                    existingAccount,
                    name: trimmedName,
                    username: username,
                    emailReference: emailReference,
                    profileURLString: profileURLString,
                    officialDashboardURLString: officialDashboardURLString,
                    accountType: accountType,
                    accountStatus: accountStatus,
                    monetizationStatus: monetizationStatus,
                    notes: notes,
                    domainExpirationDate: enableDomainExpiration ? domainExpirationDate : nil
                )

                // Check if platform changed; reassign category if needed
                if existingAccount.platform != selectedPlatform.rawValue {
                    var newCategory = categories.first { $0.name == selectedPlatform.rawValue }
                    if newCategory == nil {
                        _ = try? CategorySeeder.seedDefaultCategoriesIfNeeded(modelContext: modelContext)
                        let descriptor = FetchDescriptor<PlatformCategory>(
                            predicate: #Predicate<PlatformCategory> { $0.name == selectedPlatform.rawValue }
                        )
                        newCategory = try? modelContext.fetch(descriptor).first
                    }
                    try service.reassignCategory(account: existingAccount, to: newCategory)
                }

                dismiss()
            } else {
                // Find matching category or seed if missing
                var category = categories.first { $0.name == selectedPlatform.rawValue }
                if category == nil {
                    _ = try? CategorySeeder.seedDefaultCategoriesIfNeeded(modelContext: modelContext)
                    let descriptor = FetchDescriptor<PlatformCategory>(
                        predicate: #Predicate<PlatformCategory> { $0.name == selectedPlatform.rawValue }
                    )
                    category = try? modelContext.fetch(descriptor).first
                }

                try service.createAccount(
                    name: trimmedName,
                    platform: selectedPlatform.rawValue,
                    username: username,
                    emailReference: emailReference,
                    profileURLString: profileURLString,
                    officialDashboardURLString: officialDashboardURLString,
                    accountType: accountType,
                    accountStatus: accountStatus,
                    monetizationStatus: monetizationStatus,
                    notes: notes,
                    domainExpirationDate: enableDomainExpiration ? domainExpirationDate : nil,
                    category: category
                )
                dismiss()
            }
        } catch {
            isSaving = false
            errorMessage = error.localizedDescription
            isShowingErrorAlert = true
        }
    }
}
