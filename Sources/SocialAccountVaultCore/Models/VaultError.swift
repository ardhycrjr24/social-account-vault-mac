import Foundation

/// Strongly-typed domain errors for Social Account Vault.
public enum VaultError: LocalizedError, Sendable, Equatable {
    case prohibitedCredentialStorage(key: String)
    case invalidFieldLength(field: String, max: Int, actual: Int)
    case invalidURL(urlString: String)
    case entityNotFound(entity: String, id: UUID)
    case persistenceFailure(reason: String)
    case migrationFailure(reason: String)
    case storageUnavailable(reason: String)
    case metadataValidationFailure(reason: String)
    case invalidTwoFactorCombination(status: String, method: String)

    public var errorDescription: String? {
        switch self {
        case .prohibitedCredentialStorage(let key):
            return "Security Invariant Violation: Credential or secret storage ('\(key)') is strictly prohibited. Social Account Vault never stores passwords, tokens, OTPs, or recovery codes."
        case .invalidFieldLength(let field, let max, let actual):
            return "Field '\(field)' exceeds maximum allowed length of \(max) characters (received \(actual))."
        case .invalidURL(let urlString):
            return "The URL '\(urlString)' is invalid. It must use http:// or https:// scheme."
        case .entityNotFound(let entity, let id):
            return "The requested \(entity) with ID \(id) was not found."
        case .persistenceFailure(let reason):
            return "Persistence operation failed: \(reason)"
        case .migrationFailure(let reason):
            return "Database migration failed: \(reason). The original database file has been preserved untouched. Writes are halted to protect your data."
        case .storageUnavailable(let reason):
            return "Secure storage is unavailable (\(reason)). Your data has not been saved. The original database file is preserved; please use Retry Storage in Settings."
        case .metadataValidationFailure(let reason):
            return "Metadata validation failed: \(reason)"
        case .invalidTwoFactorCombination(let status, let method):
            return "Kombinasi status 2FA '\(status)' dengan metode '\(method)' tidak didukung."
        }
    }
}
