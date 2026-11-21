import Foundation
import SwiftData

/// Core entity representing a registered digital account in the vault.
///
/// Security Invariant:
/// Under no circumstances shall passwords, OTPs, recovery codes, or private credentials
/// be stored in this model or persisted anywhere in the database.
@Model
public final class Account {
    @Attribute(.unique)
    public var id: UUID
    public var name: String
    public var platform: String
    public var username: String
    public var emailReference: String
    public var profileURLString: String
    public var officialDashboardURLString: String
    public var accountTypeRaw: String
    public var accountStatusRaw: String
    public var monetizationStatusRaw: String
    public var notes: String
    public var isArchived: Bool
    public var creationDate: Date
    public var lastCheckedDate: Date
    public var domainExpirationDate: Date?
    public var createdAt: Date
    public var updatedAt: Date

    // MARK: - Phase 4 Core Attributes (Strategy C)
    // Lightweight additions with native defaults so V1.0 stores migrate cleanly.
    // Defaults are declared on the properties themselves so SwiftData can
    // back-fill existing rows during lightweight migration.

    /// Direct login URL (https only). Empty string when unset.
    public var directLoginURLString: String = ""
    /// Recovery email reference (sensitive personal data, validated). Empty when unset.
    public var recoveryEmailReference: String = ""
    /// Masked recovery phone hint only (e.g. "•••• 8899"). Never a full number.
    public var recoveryPhoneHint: String = ""
    /// Raw value of `TwoFactorStatus`. Defaults to "unknown".
    public var twoFactorStatusRaw: String = TwoFactorStatus.default.rawValue
    /// Raw value of `TwoFactorMethod`. Defaults to "none".
    public var twoFactorMethodRaw: String = TwoFactorMethod.default.rawValue
    /// Primary assigned device hardware name. Empty when unset.
    public var primaryDeviceName: String = ""
    /// Raw value of `DeviceOSType`. Defaults to "macOS".
    public var deviceOSRaw: String = DeviceOSType.default.rawValue
    /// Historical timestamp of last password rotation. Metadata only — NO password stored.
    public var passwordLastRotatedDate: Date?

    public var category: PlatformCategory?

    @Relationship(deleteRule: .cascade, inverse: \AccountDetail.account)
    public var details: [AccountDetail] = []

    @Relationship(deleteRule: .cascade, inverse: \ActivityLog.account)
    public var activityLogs: [ActivityLog] = []

    public init(
        id: UUID = UUID(),
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
        isArchived: Bool = false,
        creationDate: Date = Date(),
        lastCheckedDate: Date = Date(),
        domainExpirationDate: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        directLoginURLString: String = "",
        recoveryEmailReference: String = "",
        recoveryPhoneHint: String = "",
        twoFactorStatus: TwoFactorStatus = .default,
        twoFactorMethod: TwoFactorMethod = .default,
        primaryDeviceName: String = "",
        deviceOS: DeviceOSType = .default,
        passwordLastRotatedDate: Date? = nil,
        category: PlatformCategory? = nil
    ) {
        self.id = id
        self.name = name
        self.platform = platform
        self.username = username
        self.emailReference = emailReference
        self.profileURLString = profileURLString
        self.officialDashboardURLString = officialDashboardURLString
        self.accountTypeRaw = accountType.rawValue
        self.accountStatusRaw = accountStatus.rawValue
        self.monetizationStatusRaw = monetizationStatus.rawValue
        self.notes = notes
        self.isArchived = isArchived
        self.creationDate = creationDate
        self.lastCheckedDate = lastCheckedDate
        self.domainExpirationDate = domainExpirationDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.directLoginURLString = directLoginURLString
        self.recoveryEmailReference = recoveryEmailReference
        self.recoveryPhoneHint = recoveryPhoneHint
        self.twoFactorStatusRaw = twoFactorStatus.rawValue
        self.twoFactorMethodRaw = twoFactorMethod.rawValue
        self.primaryDeviceName = primaryDeviceName
        self.deviceOSRaw = deviceOS.rawValue
        self.passwordLastRotatedDate = passwordLastRotatedDate
        self.category = category
    }

    // MARK: - Enums Accessors

    public var accountType: AccountType {
        get { AccountType(rawValue: accountTypeRaw) ?? .personal }
        set {
            accountTypeRaw = newValue.rawValue
            updatedAt = Date()
        }
    }

    public var accountStatus: AccountStatus {
        get { AccountStatus(rawValue: accountStatusRaw) ?? .active }
        set {
            accountStatusRaw = newValue.rawValue
            updatedAt = Date()
        }
    }

    public var monetizationStatus: MonetizationStatus {
        get { MonetizationStatus(rawValue: monetizationStatusRaw) ?? .notMonetized }
        set {
            monetizationStatusRaw = newValue.rawValue
            updatedAt = Date()
        }
    }

    // MARK: - Phase 4 Typed Accessors

    public var twoFactorStatus: TwoFactorStatus {
        get { TwoFactorStatus(rawValue: twoFactorStatusRaw) ?? .default }
        set {
            twoFactorStatusRaw = newValue.rawValue
            updatedAt = Date()
        }
    }

    public var twoFactorMethod: TwoFactorMethod {
        get { TwoFactorMethod(rawValue: twoFactorMethodRaw) ?? .default }
        set {
            twoFactorMethodRaw = newValue.rawValue
            updatedAt = Date()
        }
    }

    public var deviceOS: DeviceOSType {
        get { DeviceOSType(rawValue: deviceOSRaw) ?? .default }
        set {
            deviceOSRaw = newValue.rawValue
            updatedAt = Date()
        }
    }

    // MARK: - Deterministic Activity Log Ordering

    /// Appends an activity log ensuring sequential numbering and strictly monotonic timestamps.
    @discardableResult
    public func appendActivityLog(actionType: String, details: String) -> ActivityLog {
        let nextSeq = (activityLogs.map(\.sequenceNumber).max() ?? 0) + 1
        var eventTime = Date()
        if let maxTime = activityLogs.map(\.timestamp).max(), eventTime <= maxTime {
            eventTime = maxTime.addingTimeInterval(0.001)
        }
        let log = ActivityLog(
            actionType: actionType,
            details: details,
            timestamp: eventTime,
            sequenceNumber: nextSeq,
            account: self
        )
        activityLogs.append(log)
        return log
    }

    /// Returns activity logs sorted deterministically by sequence and timestamp (earliest to latest).
    public var sortedActivityLogs: [ActivityLog] {
        activityLogs.sorted { lhs, rhs in
            if lhs.sequenceNumber != rhs.sequenceNumber {
                return lhs.sequenceNumber < rhs.sequenceNumber
            }
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp < rhs.timestamp
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    // MARK: - Domain Operations

    /// Reassigns this account to a different platform category without data loss.
    public func reassignCategory(_ newCategory: PlatformCategory?) {
        let oldCategoryName = self.category?.name ?? "None"
        self.category = newCategory
        if let newCategory = newCategory {
            self.platform = newCategory.name
        }
        self.updatedAt = Date()

        appendActivityLog(
            actionType: "Category Reassigned",
            details: "Category changed from '\(oldCategoryName)' to '\(newCategory?.name ?? "None")'"
        )
    }

    /// Archives this account, removing it from active views.
    public func archive() {
        self.isArchived = true
        self.updatedAt = Date()

        appendActivityLog(
            actionType: "Archived",
            details: "Account moved to archive"
        )
    }

    /// Restores this account from the archive back to active status.
    public func restore() {
        self.isArchived = false
        self.updatedAt = Date()

        appendActivityLog(
            actionType: "Restored",
            details: "Account restored from archive to active status"
        )
    }

    /// Records that the account was verified by the user.
    public func markChecked() {
        let now = Date()
        self.lastCheckedDate = now
        self.updatedAt = now

        appendActivityLog(
            actionType: "Status Checked",
            details: "Manual account status check recorded"
        )
    }

    /// Validates profile URL string for correct http/https syntax.
    public var hasValidProfileURL: Bool {
        guard !profileURLString.isEmpty, let url = URL(string: profileURLString) else {
            return false
        }
        return url.scheme == "https" || url.scheme == "http"
    }

    /// Validates official dashboard URL string for correct http/https syntax.
    public var hasValidOfficialDashboardURL: Bool {
        guard !officialDashboardURLString.isEmpty, let url = URL(string: officialDashboardURLString) else {
            return false
        }
        return url.scheme == "https" || url.scheme == "http"
    }
}
