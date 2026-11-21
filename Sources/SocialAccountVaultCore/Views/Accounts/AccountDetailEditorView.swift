import SwiftUI
import SwiftData

/// Editor terperinci untuk metadata Phase 4 (Task 4).
/// Menangani recovery, 2FA, device, direct login, standard metadata, dan monetization.
///
/// Prinsip:
/// - Semua tulis melalui VaultDataService (StorageCoordinator guard).
/// - Tidak ada mutasi SwiftData langsung dari View.
/// - Error validasi ditampilkan di dekat field; input pengguna tidak hilang saat gagal.
/// - Tidak pernah menampilkan/menyimpan credential atau data recovery lengkap di log.
@MainActor
public struct AccountDetailEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(StorageCoordinator.self) private var storage
    @Environment(\.domainRegistry) private var domainRegistry

    @Bindable public var account: Account

    // Recovery (dimasking)
    @State private var recoveryEmail: String
    @State private var recoveryPhoneHint: String
    @State private var recoveryEmailError: String?
    @State private var phoneError: String?
    @State private var rotationEnabled: Bool
    @State private var rotationDate: Date
    @State private var rotationError: String?
    @State private var storedRotationDate: Date?
    @State private var showRotationDeleteConfirm = false

    // 2FA
    @State private var twoFactorStatus: TwoFactorStatus
    @State private var twoFactorMethod: TwoFactorMethod
    @State private var twoFactorError: String?

    // Device
    @State private var primaryDeviceName: String
    @State private var deviceOS: DeviceOSType

    // Direct login URL
    @State private var directLoginURL: String
    @State private var loginHostname: String?
    @State private var loginDecision: URLSafetyDecision?
    @State private var isShowingLoginConfirmation = false

    // Standard metadata + advisory
    @State private var metadataKey: StandardMetadataKey = .youtubeChannelID
    @State private var metadataValue: String = ""
    @State private var metadataCategory: MetadataCategory = .platformIdentifier
    @State private var metadataAdvisory: MetadataValidation?
    @State private var metadataMessage: String?

    // Monetization
    @State private var payoutSchedule: String
    @State private var payoutCurrency: String

    // Global
    @State private var errorMessage: String?
    @State private var isShowingErrorAlert = false
    @State private var isSaving = false

    private let metadataValidator = MetadataValidator()
    private let urlValidator = URLSafetyValidator()

    public init(account: Account) {
        self.account = account
        _recoveryEmail = State(initialValue: account.recoveryEmailReference)
        _recoveryPhoneHint = State(initialValue: account.recoveryPhoneHint)
        _rotationEnabled = State(initialValue: account.passwordLastRotatedDate != nil)
        _rotationDate = State(initialValue: account.passwordLastRotatedDate ?? Date())
        _storedRotationDate = State(initialValue: account.passwordLastRotatedDate)
        _twoFactorStatus = State(initialValue: account.twoFactorStatus)
        _twoFactorMethod = State(initialValue: account.twoFactorMethod)
        _primaryDeviceName = State(initialValue: account.primaryDeviceName)
        _deviceOS = State(initialValue: account.deviceOS)
        _directLoginURL = State(initialValue: account.directLoginURLString)

        let schedule = account.details.first { $0.key == StandardMetadataKey.payoutSchedule.rawValue }?.value ?? ""
        let currency = account.details.first { $0.key == StandardMetadataKey.payoutCurrency.rawValue }?.value ?? ""
        _payoutSchedule = State(initialValue: schedule)
        _payoutCurrency = State(initialValue: currency)
    }

    public var body: some View {
        NavigationStack {
            Form {
                recoverySection
                twoFactorSection
                deviceSection
                loginSection
                metadataSection
                monetizationSection
                securityNotice
            }
            .formStyle(.grouped)
            .navigationTitle("Detail Akun")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Simpan") { saveAll() }
                        .disabled(isSaving || !storage.status.isWritable)
                }
            }
            .alert("Gagal Menyimpan", isPresented: $isShowingErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Terjadi kesalahan.")
            }
            .confirmationDialog(
                "Hapus Tanggal Rotasi?",
                isPresented: $showRotationDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Hapus", role: .destructive) { deletePasswordRotationDate() }
                Button("Batal", role: .cancel) {}
            } message: {
                Text("Tanggal historis rotasi kata sandi akan dihapus permanen dan tidak dapat dikembalikan.")
            }
            .alert("Periksa URL Login", isPresented: $isShowingLoginConfirmation) {
                Button("Batal", role: .cancel) {}
                Button("Tetap Simpan", role: .destructive) { saveLoginURL(force: true) }
            } message: {
                Text("Hostname: \(loginHostname ?? "-")\n\(loginDecision?.reasons.joined(separator: "\n") ?? "")")
            }
            .onChange(of: metadataKey) { _, newKey in
                metadataCategory = newKey.category
                metadataAdvisory = nil
                metadataMessage = nil
            }
        }
        .frame(minWidth: 540, idealWidth: 600, minHeight: 560)
    }

    // MARK: - Sections

    private var recoverySection: some View {
        Section("Informasi Recovery") {
            TextField("Email recovery (opsional)", text: $recoveryEmail)
                .textFieldStyle(.roundedBorder)
            if let error = recoveryEmailError {
                Text(error).font(.caption).foregroundColor(.red)
            }

            TextField("Petunjuk telepon (mis. •••• 8899)", text: $recoveryPhoneHint)
                .textFieldStyle(.roundedBorder)
            if let error = phoneError {
                Text(error).font(.caption).foregroundColor(.red)
            }
            Text("Hanya 4 digit terakhir yang boleh disimpan. Nomor lengkap tidak disimpan.")
                .font(.caption2).foregroundColor(.secondary)

            Toggle("Catat tanggal rotasi kata sandi", isOn: $rotationEnabled)
            if rotationEnabled {
                DatePicker("Tanggal rotasi", selection: $rotationDate, displayedComponents: [.date])
                Text("Hanya tanggal historis (tidak boleh di masa depan).")
                    .font(.caption2).foregroundColor(.secondary)
            }
            if let error = rotationError {
                Text(error).font(.caption).foregroundColor(.red)
            }
            // Penghapusan historis hanya lewat aksi eksplisit + konfirmasi.
            // Toggle OFF TIDAK menghapus tanggal yang tersimpan.
            if storedRotationDate != nil {
                Button(role: .destructive) {
                    showRotationDeleteConfirm = true
                } label: {
                    Label("Hapus tanggal rotasi", systemImage: "trash")
                }
            }
        }
    }

    private var twoFactorRequiresNone: Bool {
        twoFactorStatus == .disabled || twoFactorStatus == .unknown
    }

    private var twoFactorSection: some View {
        Section("Two-Factor Authentication") {
            Picker("Status", selection: $twoFactorStatus) {
                ForEach(TwoFactorStatus.allCases) { status in
                    Label(status.rawValue, systemImage: status.iconName).tag(status)
                }
            }
            Picker("Metode", selection: $twoFactorMethod) {
                ForEach(TwoFactorMethod.allCases) { method in
                    Label(method.rawValue, systemImage: method.iconName).tag(method)
                }
            }
            .disabled(twoFactorRequiresNone)
            if twoFactorRequiresNone {
                Text("Status '\(twoFactorStatus.rawValue)' hanya mendukung metode 'none'.")
                    .font(.caption2).foregroundColor(.secondary)
            } else if twoFactorStatus == .enforcedByOrg && twoFactorMethod == .none {
                Text("Organisasi menerapkan 2FA, tetapi metode tidak dicatat.")
                    .font(.caption2).foregroundColor(.secondary)
            }
            if let error = twoFactorError {
                Text(error).font(.caption).foregroundColor(.red)
            }
        }
    }

    private var deviceSection: some View {
        Section("Perangkat Utama") {
            TextField("Nama perangkat (opsional)", text: $primaryDeviceName)
                .textFieldStyle(.roundedBorder)
            Picker("Sistem Operasi", selection: $deviceOS) {
                ForEach(DeviceOSType.allCases) { os in
                    Label(os.rawValue, systemImage: os.iconName).tag(os)
                }
            }
        }
    }

    private var loginSection: some View {
        Section("Direct Login URL") {
            TextField("https://... (opsional)", text: $directLoginURL)
                .textFieldStyle(.roundedBorder)
            if let host = loginHostname {
                Label("Hostname: \(host)", systemImage: "server.rack")
                    .font(.caption).foregroundColor(.secondary)
            }
            Text("URL tidak dibuka otomatis. Tautan mencurigakan memerlukan konfirmasi.")
                .font(.caption2).foregroundColor(.secondary)
        }
    }

    private var metadataSection: some View {
        Section("Standard Metadata") {
            Picker("Jenis", selection: $metadataKey) {
                ForEach(StandardMetadataKey.allCases) { key in
                    Text(key.rawValue).tag(key)
                }
            }
            Picker("Kategori", selection: $metadataCategory) {
                ForEach(MetadataCategory.allCases) { cat in
                    Text(cat.displayName).tag(cat)
                }
            }
            TextField("Nilai", text: $metadataValue)
                .textFieldStyle(.roundedBorder)
            if let advisory = metadataAdvisory {
                advisoryView(advisory)
            }
            if let message = metadataMessage {
                Text(message).font(.caption).foregroundColor(.secondary)
            }
            Button("Simpan Metadata") { saveMetadata() }
                .disabled(!storage.status.isWritable || metadataValue.isEmpty)
        }
    }

    private var monetizationSection: some View {
        Section("Monetisasi") {
            TextField("Jadwal (monthly / net30 / biweekly)", text: $payoutSchedule)
                .textFieldStyle(.roundedBorder)
            TextField("Mata uang ISO (mis. USD)", text: $payoutCurrency)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var securityNotice: some View {
        Section {
            Text("Vault hanya menyimpan metadata operasional non-sensitif. Kata sandi, token, OTP, dan kode recovery tidak pernah diminta atau disimpan.")
                .font(.caption2).foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func advisoryView(_ advisory: MetadataValidation) -> some View {
        switch advisory {
        case .valid:
            Label("VALID", systemImage: "checkmark.circle.fill").foregroundColor(.green).font(.caption)
        case .warning(let reason):
            Label("WARNING: \(reason)", systemImage: "exclamationmark.triangle").foregroundColor(.orange).font(.caption)
        case .unknown(let reason):
            Label("UNKNOWN: \(reason)", systemImage: "questionmark.circle").foregroundColor(.secondary).font(.caption)
        case .invalid(let reason):
            Label("INVALID: \(reason)", systemImage: "xmark.circle").foregroundColor(.red).font(.caption)
        }
    }

    // MARK: - Actions

    private func saveAll() {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        // Validasi awal tanpa menimpa input pengguna.
        let emailResult = metadataValidator.validateRecoveryEmail(recoveryEmail)
        let phoneResult = metadataValidator.validateRecoveryPhoneHint(recoveryPhoneHint)
        recoveryEmailError = emailResult.isAccepted ? nil : emailResult.reason
        phoneError = phoneResult.isAccepted ? nil : phoneResult.reason
        // Toggle OFF tidak membersihkan tanggal historis — tidak ada validasi/pembersihan di sini.
        let rotationResult = rotationEnabled
            ? metadataValidator.validatePasswordRotationDate(rotationDate)
            : .valid
        rotationError = rotationResult.isAccepted ? nil : rotationResult.reason
        guard emailResult.isAccepted, phoneResult.isAccepted, rotationResult.isAccepted else {
            errorMessage = "Periksa kolom yang ditandai."
            isShowingErrorAlert = true
            return
        }

        if !directLoginURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let decision = urlValidator.classify(
                directLoginURL, platform: account.platform, registry: domainRegistry
            )
            loginDecision = decision
            loginHostname = decision.hostname
            if case .blocked(let reasons) = decision {
                errorMessage = reasons.joined(separator: " ")
                isShowingErrorAlert = true
                return
            }
            if case .warning = decision {
                isShowingLoginConfirmation = true
                return
            }
        }

        commitAll()
    }

    private func saveLoginURL(force: Bool) {
        isSaving = true
        defer { isSaving = false }
        guard force else { return }
        commitAll()
    }

    /// Penghapusan eksplisit tanggal rotasi historis (setelah konfirmasi dialog).
    private func deletePasswordRotationDate() {
        let service = VaultDataService(modelContext: modelContext, storageGate: storage)
        do {
            _ = try service.removePasswordRotationDate(account)
            storedRotationDate = nil
            rotationEnabled = false
        } catch {
            errorMessage = error.localizedDescription
            isShowingErrorAlert = true
        }
    }

    private func commitAll() {
        let service = VaultDataService(modelContext: modelContext, storageGate: storage)
        do {
            _ = try service.setRecoveryEmail(account, value: recoveryEmail)
            _ = try service.setRecoveryPhoneHint(account, value: recoveryPhoneHint)
            if rotationEnabled {
                _ = try service.setPasswordRotationDate(account, date: rotationDate)
            }

            let method: TwoFactorMethod = twoFactorRequiresNone ? .none : twoFactorMethod
            guard twoFactorStatus.allows(method: method) else {
                twoFactorError = "Kombinasi status dan metode 2FA tidak didukung."
                errorMessage = twoFactorError
                isShowingErrorAlert = true
                return
            }
            try service.setTwoFactor(account: account, status: twoFactorStatus, method: method)
            twoFactorError = nil
            if method != twoFactorMethod { twoFactorMethod = method }

            // Nama perangkat disimpan lewat service update (field sudah ada di model).
            if account.primaryDeviceName != primaryDeviceName.trimmingCharacters(in: .whitespacesAndNewlines) {
                try service.setDeviceName(account, value: primaryDeviceName)
            }
            try service.setDeviceOS(account, os: deviceOS)

            if !directLoginURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try service.setDirectLoginURL(account, value: directLoginURL)
            }

            // Monetization bila diisi.
            if !payoutSchedule.isEmpty {
                _ = try service.setStandardMetadata(
                    on: account, key: .payoutSchedule, value: payoutSchedule,
                    expectedCategory: .monetization
                )
            }
            if !payoutCurrency.isEmpty {
                _ = try service.setStandardMetadata(
                    on: account, key: .payoutCurrency, value: payoutCurrency,
                    expectedCategory: .monetization
                )
            }
            // Sinkronkan cache tampilan dengan nilai tersimpan.
            storedRotationDate = account.passwordLastRotatedDate
            if storedRotationDate == nil { rotationEnabled = false }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isShowingErrorAlert = true
        }
    }

    private func saveMetadata() {
        let result = metadataValidator.validateIdentifier(metadataValue, for: metadataKey)
        let categoryResult = metadataValidator.validateCategory(key: metadataKey, expected: metadataCategory)
        metadataAdvisory = result
        guard result.isAccepted else {
            metadataMessage = "Metadata tidak disimpan."
            return
        }
        guard categoryResult.isAccepted else {
            metadataMessage = "Kategori tidak sesuai dengan jenis key."
            return
        }
        let service = VaultDataService(modelContext: modelContext, storageGate: storage)
        do {
            _ = try service.setStandardMetadata(
                on: account, key: metadataKey, value: metadataValue,
                expectedCategory: metadataCategory
            )
            metadataMessage = "Metadata tersimpan."
        } catch {
            metadataMessage = error.localizedDescription
        }
    }
}
