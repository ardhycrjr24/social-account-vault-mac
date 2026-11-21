import Testing
import Foundation
import SwiftData
@testable import SocialAccountVaultCore

/// Phase 4.1 — Security Scanner Hardening regression tests.
///
/// Verifies the hardened runtime credential validation rejects whole-word,
/// camelCase, snake_case, and uppercase credential identifiers, while legitimate
/// operational metadata and the `passwordLastRotatedDate` rotation timestamp
/// remain allowed. Comments/documentation false-positive coverage for the static
/// scanner is exercised separately via scripts/verify_code_integrity.py.
@Suite("Security Scanner Hardening Tests")
struct ScannerHardeningTests {

    // MARK: - Credentials That MUST Be Rejected (metadata keys)

    @Test("Reject whole-word credential keys")
    @MainActor
    func testRejectWholeWordCredentials() {
        let keys = ["password", "token", "secret", "otp", "private_key", "passphrase", "oauth"]
        for key in keys {
            #expect(throws: VaultError.self, "whole-word '\(key)' must be rejected") {
                try AccountDetail.validate(key: key, value: "dummy")
            }
        }
    }

    @Test("Reject camelCase compound credential keys")
    @MainActor
    func testRejectCamelCaseCredentials() {
        let keys = ["accessToken", "oauthSecret", "otpSeed", "privateKey", "sessionToken",
                    "refreshToken", "apiKey", "recoveryCode", "sessionCookie"]
        for key in keys {
            #expect(throws: VaultError.self, "camelCase '\(key)' must be rejected") {
                try AccountDetail.validate(key: key, value: "dummy")
            }
        }
    }

    @Test("Reject snake_case compound credential keys")
    @MainActor
    func testRejectSnakeCaseCredentials() {
        let keys = ["access_token", "refresh_token", "private_key", "api_key",
                    "recovery_code", "session_cookie", "oauth_secret", "otp_seed"]
        for key in keys {
            #expect(throws: VaultError.self, "snake_case '\(key)' must be rejected") {
                try AccountDetail.validate(key: key, value: "dummy")
            }
        }
    }

    @Test("Reject uppercase and mixed-case credential keys")
    @MainActor
    func testRejectUppercaseCredentials() {
        let keys = ["PASSWORD", "PrivateKey", "ACCESSTOKEN", "OAuthSecret",
                    "SESSION_TOKEN", "OTP_SEED", "ReCoVeRy_CoDe", "Api_Key"]
        for key in keys {
            #expect(throws: VaultError.self, "case-variant '\(key)' must be rejected") {
                try AccountDetail.validate(key: key, value: "dummy")
            }
        }
    }

    @Test("Reject credential keys embedded in longer identifiers")
    @MainActor
    func testRejectEmbeddedCredentials() {
        let keys = ["account_accessToken_v2", "my_privateKey_backup", "userPasswordHash",
                    "legacy_sessionToken", "prod_oauthSecret"]
        for key in keys {
            #expect(throws: VaultError.self, "embedded '\(key)' must be rejected") {
                try AccountDetail.validate(key: key, value: "dummy")
            }
        }
    }

    // MARK: - Legitimate Metadata That MUST Be Allowed

    @Test("Allow legitimate operational metadata keys")
    @MainActor
    func testAllowOperationalMetadata() throws {
        let pairs: [(String, String)] = [
            (StandardMetadataKey.youtubeChannelID.rawValue, "UC_abc123"),
            (StandardMetadataKey.metaPageID.rawValue, "1234567890"),
            (StandardMetadataKey.adsensePublisherID.rawValue, "pub-1234567890"),
            (StandardMetadataKey.cloudflareZoneID.rawValue, "cf_zone_abc"),
            (StandardMetadataKey.primaryNameserver.rawValue, "ns1.cloudflare.com"),
            (StandardMetadataKey.domainRegistrar.rawValue, "Namecheap"),
            (StandardMetadataKey.payoutCurrency.rawValue, "USD"),
            (StandardMetadataKey.payoutSchedule.rawValue, "monthly"),
            (StandardMetadataKey.workstationLocation.rawValue, "Home Studio"),
            (StandardMetadataKey.browserProfileName.rawValue, "Work Profile"),
            ("Channel ID", "UC_xyz"),
            ("Display Name", "Main Channel")
        ]
        for (key, value) in pairs {
            #expect(throws: Never.self, "metadata '\(key)' must be allowed") {
                try AccountDetail.validate(key: key, value: value)
            }
        }
    }

    // MARK: - passwordLastRotatedDate Is Legitimate Model Metadata

    @Test("passwordLastRotatedDate is a valid Account field, not a credential")
    @MainActor
    func testPasswordLastRotatedDateIsAllowedField() throws {
        // The rotation timestamp is a typed Date? property on Account. It stores
        // ONLY a date and must never be treated as credential storage. Setting it
        // must succeed and persist without throwing.
        let container = try DatabaseConfiguration.createModelContainer(inMemory: true)
        let context = ModelContext(container)
        let account = Account(name: "Rotation Test", platform: "YouTube")
        context.insert(account)
        let rotationDate = Date(timeIntervalSince1970: 1_700_000_000)
        account.passwordLastRotatedDate = rotationDate
        #expect(account.passwordLastRotatedDate == rotationDate)
        #expect(throws: Never.self) { try context.save() }

        // Re-fetch and confirm the date survived; nil default semantics intact.
        let fetched = try context.fetch(FetchDescriptor<Account>()).first
        #expect(fetched?.passwordLastRotatedDate == rotationDate)
        #expect(fetched?.twoFactorStatus == .unknown, "safe default intact")
    }

    @Test("New Phase 4 fields default safely and are not credential storage")
    @MainActor
    func testPhase4FieldsAreNonCredential() throws {
        let container = try DatabaseConfiguration.createModelContainer(inMemory: true)
        let context = ModelContext(container)
        let account = Account(name: "Defaults Test", platform: "Instagram")
        context.insert(account)
        try context.save()
        #expect(account.passwordLastRotatedDate == nil)
        #expect(account.recoveryEmailReference == "")
        #expect(account.recoveryPhoneHint == "")
        #expect(account.twoFactorStatusRaw == "unknown")
        #expect(account.twoFactorMethodRaw == "none")
        #expect(account.deviceOSRaw == "macOS")
    }

    // MARK: - VaultDataService Runtime Scanner (username & notes)

    @Test("VaultDataService rejects camelCase and snake_case credentials in notes")
    @MainActor
    func testServiceRejectsCompoundCredentialsInNotes() throws {
        let container = try DatabaseConfiguration.createModelContainer(inMemory: true)
        let context = ModelContext(container)
        let service = VaultDataService(modelContext: context)
        let payloads = ["accessToken: eyJabc", "my_privateKey_here", "oauthSecret=xyz",
                        "otpSeed 12345", "sessionToken abc", "PASSWORD hunter2"]
        for payload in payloads {
            #expect(throws: VaultError.self, "notes '\(payload)' must be rejected") {
                try service.createAccount(name: "Acct", platform: "YouTube", username: "user", notes: payload)
            }
        }
    }

    @Test("VaultDataService allows clean operational notes")
    @MainActor
    func testServiceAllowsCleanNotes() throws {
        let container = try DatabaseConfiguration.createModelContainer(inMemory: true)
        let context = ModelContext(container)
        let service = VaultDataService(modelContext: context)
        #expect(throws: Never.self) {
            try service.createAccount(
                name: "Clean Acct",
                platform: "YouTube",
                username: "creator",
                notes: "Upload schedule: weekly.\nRunbook: review analytics monthly."
            )
        }
    }
}