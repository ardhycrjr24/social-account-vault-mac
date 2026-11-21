import Foundation
import SwiftData

/// Flexible key-value metadata item attached to an Account (e.g., Publisher ID, Nameserver, Channel Handle).
///
/// Security Invariant:
/// Never store credentials, authentication secrets, passwords, OTPs, or recovery codes in this entity.
/// All keys and values are strictly bounded and verified against prohibited credential patterns.
@Model
public final class AccountDetail {
    public static let maxKeyLength = 100
    public static let maxValueLength = 1000

    @Attribute(.unique)
    public var id: UUID
    public var key: String
    public var value: String
    public var createdAt: Date
    public var updatedAt: Date

    public var account: Account?

    public init(
        id: UUID = UUID(),
        key: String,
        value: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        account: Account? = nil
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.account = account
    }

    /// Validates key and value constraints and updates the record.
    public func update(key: String, value: String) throws {
        try Self.validate(key: key, value: value)
        self.key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        self.value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        self.updatedAt = Date()
    }

    /// Enforces length boundaries and zero credential storage policy.
    public static func validate(key: String, value: String) throws {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedKey.isEmpty else {
            throw VaultError.invalidFieldLength(field: "Metadata Key", max: maxKeyLength, actual: 0)
        }

        guard trimmedKey.count <= maxKeyLength else {
            throw VaultError.invalidFieldLength(field: "Metadata Key", max: maxKeyLength, actual: trimmedKey.count)
        }

        guard trimmedValue.count <= maxValueLength else {
            throw VaultError.invalidFieldLength(field: "Metadata Value", max: maxValueLength, actual: trimmedValue.count)
        }

        // Security Invariant Check: Reject prohibited credential patterns.
        // Hardened (Phase 4.1): includes underscore-free camelCase compounds so
        // privateKey / accessToken / oauthSecret / otpSeed / sessionToken are
        // rejected in addition to snake_case and whole-word forms. Matching is
        // substring-based on the lowercased key, covering any letter-case mix.
        let lowerKey = trimmedKey.lowercased()
        let forbiddenKeyPatterns = [
            "password", "passphrase", "oauth", "token", "secret",
            "private_key", "privatekey", "otp", "2fa", "recovery_code",
            "recoverycode", "session_cookie", "sessioncookie", "api_key",
            "apikey", "credential", "accesstoken", "refreshtoken",
            "oauthsecret", "otpseed", "sessiontoken"
        ]

        for pattern in forbiddenKeyPatterns {
            if lowerKey.contains(pattern) {
                throw VaultError.prohibitedCredentialStorage(key: trimmedKey)
            }
        }
    }
}
