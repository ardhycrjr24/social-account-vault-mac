import Foundation
import SwiftData

/// Dedicated service for performing validated CRUD and audit operations on the vault.
@MainActor
public final class VaultDataService: Sendable {
    private let modelContext: ModelContext
    /// Sumber kebenaran status storage. Bila disediakan, semua operasi tulis
    /// diverifikasi terhadap status ini — bukan hanya mengandalkan UI.
    private let storageGate: StorageCoordinator?

    public init(modelContext: ModelContext, storageGate: StorageCoordinator? = nil) {
        self.modelContext = modelContext
        self.storageGate = storageGate
    }

    /// Guard tunggal untuk seluruh operasi modifikasi database.
    private func guardWritable() throws {
        try storageGate?.requireWritable()
    }

    // MARK: - Account CRUD Operations

    /// Registers a new account in the vault with strict input length and security validation.
    @discardableResult
    public func createAccount(
        name: String,
        platform: String,
        username: String = "",
        emailReference: String = "",
        profileURLString: String = "",
        officialDashboardURLString: String = "",
        accountType: AccountType = .personal,
        accountStatus: AccountStatus = .active,
        monetizationStatus: MonetizationStatus = .notMonetized,
        notes: String = "",
        domainExpirationDate: Date? = nil,
        category: PlatformCategory? = nil
    ) throws -> Account {
        try guardWritable()
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw VaultError.invalidFieldLength(field: "Account Name", max: 100, actual: 0)
        }
        guard trimmedName.count <= 100 else {
            throw VaultError.invalidFieldLength(field: "Account Name", max: 100, actual: trimmedName.count)
        }

        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedUsername.count <= 100 else {
            throw VaultError.invalidFieldLength(field: "Username", max: 100, actual: trimmedUsername.count)
        }

        let trimmedEmail = emailReference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedEmail.count <= 150 else {
            throw VaultError.invalidFieldLength(field: "Email Reference", max: 150, actual: trimmedEmail.count)
        }

        let trimmedProfileURL = profileURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedProfileURL.isEmpty {
            guard let url = URL(string: trimmedProfileURL), url.scheme == "https" || url.scheme == "http" else {
                throw VaultError.invalidURL(urlString: trimmedProfileURL)
            }
        }

        let trimmedDashboardURL = officialDashboardURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDashboardURL.isEmpty {
            guard let url = URL(string: trimmedDashboardURL), url.scheme == "https" || url.scheme == "http" else {
                throw VaultError.invalidURL(urlString: trimmedDashboardURL)
            }
        }

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedNotes.count <= 4000 else {
            throw VaultError.invalidFieldLength(field: "Notes", max: 4000, actual: trimmedNotes.count)
        }

        // Security Invariant Check: Reject prohibited credential patterns
        let forbidden = ["password", "passphrase", "oauth", "token", "secret", "private_key", "privatekey", "otp", "2fa", "recovery_code", "recoverycode", "session_cookie", "sessioncookie", "api_key", "apikey", "credential", "accesstoken", "refreshtoken", "oauthsecret", "otpseed", "sessiontoken"]
        for word in forbidden {
            if trimmedUsername.lowercased().contains(word) {
                throw VaultError.prohibitedCredentialStorage(key: "Username contains '\(word)'")
            }
            if trimmedNotes.lowercased().contains(word) {
                throw VaultError.prohibitedCredentialStorage(key: "Notes contain '\(word)'")
            }
        }

        // Auto-resolve category if not provided
        var resolvedCategory = category
        if resolvedCategory == nil {
            let catDescriptor = FetchDescriptor<PlatformCategory>(
                predicate: #Predicate<PlatformCategory> { $0.name == platform }
            )
            resolvedCategory = try? modelContext.fetch(catDescriptor).first
        }

        let account = Account(
            name: trimmedName,
            platform: platform,
            username: trimmedUsername,
            emailReference: trimmedEmail,
            profileURLString: trimmedProfileURL,
            officialDashboardURLString: trimmedDashboardURL,
            accountType: accountType,
            accountStatus: accountStatus,
            monetizationStatus: monetizationStatus,
            notes: trimmedNotes,
            domainExpirationDate: domainExpirationDate,
            category: resolvedCategory
        )

        modelContext.insert(account)
        account.appendActivityLog(
            actionType: "Created",
            details: "Account registered in vault under platform '\(platform)'"
        )

        try modelContext.save()
        return account
    }

    /// Updates core account attributes and creates an audit record if changes are detected.
    /// Returns true if changes were applied, or false if no actual modification occurred.
    @discardableResult
    public func updateAccount(
        _ account: Account,
        name: String,
        username: String,
        emailReference: String,
        profileURLString: String,
        officialDashboardURLString: String,
        accountType: AccountType,
        accountStatus: AccountStatus,
        monetizationStatus: MonetizationStatus,
        notes: String,
        domainExpirationDate: Date? = nil
    ) throws -> Bool {
        try guardWritable()
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw VaultError.invalidFieldLength(field: "Account Name", max: 100, actual: 0)
        }
        guard trimmedName.count <= 100 else {
            throw VaultError.invalidFieldLength(field: "Account Name", max: 100, actual: trimmedName.count)
        }

        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedUsername.count <= 100 else {
            throw VaultError.invalidFieldLength(field: "Username", max: 100, actual: trimmedUsername.count)
        }

        let trimmedEmail = emailReference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedEmail.count <= 150 else {
            throw VaultError.invalidFieldLength(field: "Email Reference", max: 150, actual: trimmedEmail.count)
        }

        let trimmedProfileURL = profileURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedProfileURL.isEmpty {
            guard let url = URL(string: trimmedProfileURL), url.scheme == "https" || url.scheme == "http" else {
                throw VaultError.invalidURL(urlString: trimmedProfileURL)
            }
        }

        let trimmedDashboardURL = officialDashboardURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDashboardURL.isEmpty {
            guard let url = URL(string: trimmedDashboardURL), url.scheme == "https" || url.scheme == "http" else {
                throw VaultError.invalidURL(urlString: trimmedDashboardURL)
            }
        }

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedNotes.count <= 4000 else {
            throw VaultError.invalidFieldLength(field: "Notes", max: 4000, actual: trimmedNotes.count)
        }

        let forbidden = ["password", "passphrase", "oauth", "token", "secret", "private_key", "privatekey", "otp", "2fa", "recovery_code", "recoverycode", "session_cookie", "sessioncookie", "api_key", "apikey", "credential", "accesstoken", "refreshtoken", "oauthsecret", "otpseed", "sessiontoken"]
        for word in forbidden {
            if trimmedUsername.lowercased().contains(word) {
                throw VaultError.prohibitedCredentialStorage(key: "Username contains '\(word)'")
            }
            if trimmedNotes.lowercased().contains(word) {
                throw VaultError.prohibitedCredentialStorage(key: "Notes contain '\(word)'")
            }
        }

        // Check if domain expiration dates are equal within 1 second tolerance
        let datesEqual: Bool
        switch (account.domainExpirationDate, domainExpirationDate) {
        case (nil, nil):
            datesEqual = true
        case (let d1?, let d2?):
            datesEqual = abs(d1.timeIntervalSince(d2)) < 1.0
        default:
            datesEqual = false
        }

        // Idempotency guard: Determine if any field actually changed
        let hasChanges = (account.name != trimmedName)
            || (account.username != trimmedUsername)
            || (account.emailReference != trimmedEmail)
            || (account.profileURLString != trimmedProfileURL)
            || (account.officialDashboardURLString != trimmedDashboardURL)
            || (account.accountType != accountType)
            || (account.accountStatus != accountStatus)
            || (account.monetizationStatus != monetizationStatus)
            || (account.notes != trimmedNotes)
            || !datesEqual

        guard hasChanges else {
            // No actual change: prevent duplicate audit logs and redundant disk writes
            return false
        }

        account.name = trimmedName
        account.username = trimmedUsername
        account.emailReference = trimmedEmail
        account.profileURLString = trimmedProfileURL
        account.officialDashboardURLString = trimmedDashboardURL
        account.accountType = accountType
        account.accountStatus = accountStatus
        account.monetizationStatus = monetizationStatus
        account.notes = trimmedNotes
        account.domainExpirationDate = domainExpirationDate
        account.updatedAt = Date()

        account.appendActivityLog(
            actionType: "Updated",
            details: "Account details updated"
        )

        try modelContext.save()
        return true
    }

    /// Rekam verifikasi manual melalui service agar tulis tetap terproteksi.
    @discardableResult
    public func markChecked(_ account: Account) throws -> ActivityLog {
        try guardWritable()
        account.markChecked()
        try modelContext.save()
        guard let log = account.activityLogs.last else {
            throw VaultError.persistenceFailure(reason: "status check audit record missing")
        }
        return log
    }

    /// Moves an account to the archive. Idempotent: arkip yang sudah aktif
    /// tidak menghasilkan log duplikat atau penulisan ulang.
    @discardableResult
    public func archiveAccount(_ account: Account) throws -> Bool {
        try guardWritable()
        guard !account.isArchived else { return false }
        account.archive()
        try modelContext.save()
        return true
    }

    /// Restores an archived account. Idempotent: akun yang sudah aktif
    /// tidak menghasilkan log duplikat atau penulisan ulang.
    @discardableResult
    public func restoreAccount(_ account: Account) throws -> Bool {
        try guardWritable()
        guard account.isArchived else { return false }
        account.restore()
        try modelContext.save()
        return true
    }

    /// Permanently deletes an account. Cascades delete to its details and activity logs.
    public func deleteAccount(_ account: Account) throws {
        try guardWritable()
        modelContext.delete(account)
        try modelContext.save()
    }

    /// Reassigns an account to a new category without losing any account data.
    public func reassignCategory(account: Account, to newCategory: PlatformCategory?) throws {
        try guardWritable()
        account.reassignCategory(newCategory)
        try modelContext.save()
    }

    // MARK: - Metadata (AccountDetail) Operations

    /// Adds a validated, non-credential key-value detail to the account.
    @discardableResult
    public func addDetail(
        to account: Account,
        key: String,
        value: String
    ) throws -> AccountDetail {
        try guardWritable()
        try AccountDetail.validate(key: key, value: value)

        let detail = AccountDetail(
            key: key.trimmingCharacters(in: .whitespacesAndNewlines),
            value: value.trimmingCharacters(in: .whitespacesAndNewlines),
            account: account
        )
        account.details.append(detail)
        account.updatedAt = Date()

        account.appendActivityLog(
            actionType: "Detail Added",
            details: "Added metadata '\(detail.key)'"
        )

        try modelContext.save()
        return detail
    }

    /// Removes a detail from the account.
    public func removeDetail(_ detail: AccountDetail) throws {
        try guardWritable()
        if let account = detail.account {
            account.updatedAt = Date()
            account.appendActivityLog(
                actionType: "Detail Removed",
                details: "Removed metadata '\(detail.key)'"
            )
        }
        modelContext.delete(detail)
        try modelContext.save()
    }

    // MARK: - Recovery & Typed Metadata Operations (Task 2)

    private let metadataValidator = MetadataValidator()

    private func requireAccepted(_ validation: MetadataValidation, field: String) throws {
        guard validation.isAccepted else {
            throw VaultError.metadataValidationFailure(
                reason: validation.reason ?? "\(field) tidak valid"
            )
        }
    }

    /// Menyimpan email recovery yang sudah divalidasi formatnya.
    /// Nilai mentah TIDAK pernah ditulis ke activity log.
    @discardableResult
    public func setRecoveryEmail(_ account: Account, value: String) throws -> MetadataValidation {
        try guardWritable()
        let result = metadataValidator.validateRecoveryEmail(value)
        try requireAccepted(result, field: "Recovery email")
        account.recoveryEmailReference = value.trimmingCharacters(in: .whitespacesAndNewlines)
        account.updatedAt = Date()
        account.appendActivityLog(actionType: "Updated", details: "Recovery email diperbarui")
        try modelContext.save()
        return result
    }

    /// Menyimpan petunjuk nomor telepon yang sudah dimasking.
    /// Nomor lengkap TIDAK pernah diterima atau ditulis ke log.
    @discardableResult
    public func setRecoveryPhoneHint(_ account: Account, value: String) throws -> MetadataValidation {
        try guardWritable()
        let result = metadataValidator.validateRecoveryPhoneHint(value)
        try requireAccepted(result, field: "Recovery phone hint")
        account.recoveryPhoneHint = value.trimmingCharacters(in: .whitespacesAndNewlines)
        account.updatedAt = Date()
        account.appendActivityLog(actionType: "Updated", details: "Petunjuk telepon recovery diperbarui")
        try modelContext.save()
        return result
    }

    /// Aturan kombinasi status/metode 2FA yang disetujui produk (V1).
    /// - enabled: metode apa pun kecuali `.none`
    /// - disabled / unknown: hanya `.none`
    /// - enforcedByOrg: semua metode (termasuk `.none` = metode tidak dicatat)
    public static func isAllowedTwoFactorCombination(
        status: TwoFactorStatus,
        method: TwoFactorMethod
    ) -> Bool {
        status.allows(method: method)
    }

    /// Mengubah status/metode 2FA hanya melalui enum — tanpa seed/rahasia.
    /// Memvalidasi kombinasi agar tidak dapat dilewati via pemanggilan langsung.
    public func setTwoFactor(account: Account, status: TwoFactorStatus, method: TwoFactorMethod) throws {
        try guardWritable()
        guard Self.isAllowedTwoFactorCombination(status: status, method: method) else {
            throw VaultError.invalidTwoFactorCombination(
                status: status.rawValue,
                method: method.rawValue
            )
        }
        account.twoFactorStatus = status
        account.twoFactorMethod = method
        account.updatedAt = Date()
        account.appendActivityLog(actionType: "Updated", details: "Pengaturan 2FA diperbarui")
        try modelContext.save()
    }

    /// Menyimpan tanggal rotasi kata sandi (metadata historis, bukan kredensial).
    /// - Toggle/pencatatan dimatikan (`date == nil`): TIDAK melakukan apa pun —
    ///   nilai historis yang tersimpan dipertahankan (keputusan produk).
    /// - Tanggal masa depan ditolak; nilai tidak diubah secara diam-diam.
    @discardableResult
    public func setPasswordRotationDate(
        _ account: Account,
        date: Date?,
        now: Date = Date()
    ) throws -> Bool {
        guard date != nil else { return false }
        try guardWritable()
        let result = metadataValidator.validatePasswordRotationDate(date, now: now)
        try requireAccepted(result, field: "Tanggal rotasi kata sandi")
        guard account.passwordLastRotatedDate != date else { return false }
        account.passwordLastRotatedDate = date
        account.updatedAt = Date()
        account.appendActivityLog(actionType: "Updated", details: "Tanggal rotasi kata sandi diperbarui")
        try modelContext.save()
        return true
    }

    /// Penghapusan EKSPLISIT tanggal rotasi historis (tindakan terpisah, dengan konfirmasi UI).
    /// Menolak bila storage gagal; data historis tetap utuh bila ditolak.
    @discardableResult
    public func removePasswordRotationDate(_ account: Account) throws -> Bool {
        try guardWritable()
        guard account.passwordLastRotatedDate != nil else { return false }
        account.passwordLastRotatedDate = nil
        account.updatedAt = Date()
        account.appendActivityLog(actionType: "Updated", details: "Tanggal rotasi kata sandi dihapus")
        try modelContext.save()
        return true
    }

    /// Mengubah nama perangkat utama (non-sensitif, maksimal 100 karakter).
    @discardableResult
    public func setDeviceName(_ account: Account, value: String) throws -> Bool {
        try guardWritable()
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 100 else {
            throw VaultError.metadataValidationFailure(reason: "Nama perangkat maksimal 100 karakter")
        }
        guard account.primaryDeviceName != trimmed else { return false }
        account.primaryDeviceName = trimmed
        account.updatedAt = Date()
        account.appendActivityLog(actionType: "Updated", details: "Nama perangkat diperbarui")
        try modelContext.save()
        return true
    }

    /// Menyimpan URL login langsung setelah klasifikasi validator.
    /// Tidak pernah membuka URL dan tidak mencatat URL mentah ke activity log.
    @discardableResult
    public func setDirectLoginURL(_ account: Account, value: String) throws -> URLSafetyDecision {
        try guardWritable()
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let decision = URLSafetyValidator().classify(trimmed, platform: account.platform)
        guard decision.isOpenable else {
            throw VaultError.metadataValidationFailure(
                reason: decision.reasons.joined(separator: " ")
            )
        }
        account.directLoginURLString = trimmed
        account.updatedAt = Date()
        account.appendActivityLog(actionType: "Updated", details: "URL login langsung diperbarui")
        try modelContext.save()
        return decision
    }

    /// Mengubah OS perangkat hanya melalui enum DeviceOSType.
    public func setDeviceOS(_ account: Account, os: DeviceOSType) throws {
        try guardWritable()
        account.deviceOS = os
        account.updatedAt = Date()
        account.appendActivityLog(actionType: "Updated", details: "Sistem operasi perangkat diperbarui")
        try modelContext.save()
    }

    /// Menyimpan metadata terstandarisasi dengan validasi identifier per-key,
    /// pengecekan konsistensi kategori, dan credential scanner yang sudah ada.
    @discardableResult
    public func setStandardMetadata(
        on account: Account,
        key: StandardMetadataKey,
        value: String,
        expectedCategory: MetadataCategory? = nil
    ) throws -> MetadataValidation {
        try guardWritable()
        try AccountDetail.validate(key: key.rawValue, value: value)

        if let expectedCategory {
            let categoryResult = metadataValidator.validateCategory(key: key, expected: expectedCategory)
            try requireAccepted(categoryResult, field: "Metadata category")
        }

        let identifierResult = metadataValidator.validateIdentifier(value, for: key)
        try requireAccepted(identifierResult, field: "Identifier")

        // Timpa nilai metadata yang sudah ada untuk key yang sama, atau buat baru.
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = account.details.first(where: { $0.key == key.rawValue }) {
            try existing.update(key: key.rawValue, value: trimmedValue)
        } else {
            let detail = AccountDetail(key: key.rawValue, value: trimmedValue, account: account)
            account.details.append(detail)
        }
        account.updatedAt = Date()
        account.appendActivityLog(
            actionType: "Updated",
            details: "Metadata '\(key.rawValue)' diperbarui"
        )
        try modelContext.save()
        return identifierResult
    }

    // MARK: - Query Operations

    /// Fetches all active (non-archived) accounts sorted by display name.
    public func fetchActiveAccounts() throws -> [Account] {
        var descriptor = FetchDescriptor<Account>(
            predicate: #Predicate<Account> { account in
                !account.isArchived
            },
            sortBy: [SortDescriptor(\Account.name, order: .forward)]
        )
        descriptor.includePendingChanges = true
        return try modelContext.fetch(descriptor)
    }

    /// Fetches all archived accounts sorted by updated date descending.
    public func fetchArchivedAccounts() throws -> [Account] {
        var descriptor = FetchDescriptor<Account>(
            predicate: #Predicate<Account> { account in
                account.isArchived
            },
            sortBy: [SortDescriptor(\Account.updatedAt, order: .reverse)]
        )
        descriptor.includePendingChanges = true
        return try modelContext.fetch(descriptor)
    }

    /// Fetches accounts belonging to a specific category.
    public func fetchAccounts(in category: PlatformCategory) throws -> [Account] {
        let categoryId = category.id
        let descriptor = FetchDescriptor<Account>(
            predicate: #Predicate<Account> { account in
                !account.isArchived && account.category?.id == categoryId
            },
            sortBy: [SortDescriptor(\Account.name, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Fetches all platform categories sorted by display order.
    public func fetchCategories() throws -> [PlatformCategory] {
        let descriptor = FetchDescriptor<PlatformCategory>(
            sortBy: [SortDescriptor(\PlatformCategory.displayOrder, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Fetches all activity logs for an account sorted deterministically by chronological order.
    public func fetchActivityLogs(for account: Account) throws -> [ActivityLog] {
        let accountId = account.id
        var descriptor = FetchDescriptor<ActivityLog>(
            predicate: #Predicate<ActivityLog> { log in
                log.account?.id == accountId
            },
            sortBy: [
                SortDescriptor(\ActivityLog.sequenceNumber, order: .forward),
                SortDescriptor(\ActivityLog.timestamp, order: .forward),
                SortDescriptor(\ActivityLog.createdAt, order: .forward)
            ]
        )
        descriptor.includePendingChanges = true
        return try modelContext.fetch(descriptor)
    }
}
