import Testing
import Foundation
import SwiftData
@testable import SocialAccountVaultCore

@Suite("Security Invariant and Bounded Metadata Tests")
struct SecurityInvariantTests {

    @Test("Verify zero credential storage rejects prohibited secret keys")
    @MainActor
    func testRejectionOfCredentialKeys() {
        let forbiddenKeys = [
            "password",
            "Account_Password",
            "OAuth_Token",
            "api_key_secret",
            "otp_code",
            "2fa_backup_phrase",
            "recovery_codes",
            "private_key",
            "session_cookie"
        ]

        for key in forbiddenKeys {
            #expect(throws: VaultError.self) {
                try AccountDetail.validate(key: key, value: "dummy_value")
            }
        }
    }

    @Test("Verify valid operational metadata keys are accepted")
    @MainActor
    func testAcceptanceOfOperationalMetadata() throws {
        let validPairs: [(String, String)] = [
            ("Channel ID", "UC_abc1234567890"),
            ("Publisher ID", "pub-1234567890123456"),
            ("Cloudflare Zone ID", "cf_zone_abcdef012345"),
            ("Domain Registrar", "Namecheap"),
            ("Nameserver 1", "ns1.cloudflare.com"),
            ("Shopee Merchant ID", "ID_SHOP_9988"),
            ("AdSense Ad Unit ID", "ca-app-pub-123/456")
        ]

        for (key, value) in validPairs {
            #expect(throws: Never.self) {
                try AccountDetail.validate(key: key, value: value)
            }
        }
    }

    @Test("Verify field length bounds enforcement")
    @MainActor
    func testFieldLengthBounds() {
        // Empty key
        #expect(throws: VaultError.self) {
            try AccountDetail.validate(key: "", value: "val")
        }

        // Key > 100 chars
        let longKey = String(repeating: "k", count: 101)
        #expect(throws: VaultError.self) {
            try AccountDetail.validate(key: longKey, value: "val")
        }

        // Value > 1000 chars
        let longValue = String(repeating: "v", count: 1001)
        #expect(throws: VaultError.self) {
            try AccountDetail.validate(key: "Valid Key", value: longValue)
        }
    }

    @Test("Verify URL validation logic on Account entity")
    @MainActor
    func testURLValidation() {
        let account = Account(
            name: "URL Test Account",
            platform: "YouTube",
            username: "tester",
            profileURLString: "https://youtube.com/@tester",
            officialDashboardURLString: "https://studio.youtube.com"
        )

        #expect(account.hasValidProfileURL == true)
        #expect(account.hasValidOfficialDashboardURL == true)

        account.profileURLString = "javascript:alert(1)"
        #expect(account.hasValidProfileURL == false)

        account.profileURLString = "file:///etc/passwd"
        #expect(account.hasValidProfileURL == false)

        account.profileURLString = ""
        #expect(account.hasValidProfileURL == false)
    }

    @Test("Verify Account creation rejects empty account name")
    @MainActor
    func testAccountNameValidation() throws {
        let container = try DatabaseConfiguration.createModelContainer(inMemory: true)
        let context = ModelContext(container)
        let service = VaultDataService(modelContext: context)

        #expect(throws: VaultError.self) {
            try service.createAccount(
                name: "   ",
                platform: "YouTube",
                username: "user"
            )
        }
    }

    @Test("Verify VaultDataService rejects passwords and credentials in notes and username")
    @MainActor
    func testAccountCredentialRejection() throws {
        let container = try DatabaseConfiguration.createModelContainer(inMemory: true)
        let context = ModelContext(container)
        let service = VaultDataService(modelContext: context)

        let prohibitedPayloads = [
            "my_super_password_99",
            "access_token: eyJhbGciOi...",
            "2fa_secret_key",
            "session_cookie_value"
        ]

        for payload in prohibitedPayloads {
            #expect(throws: VaultError.self) {
                try service.createAccount(
                    name: "Secure Account",
                    platform: "YouTube",
                    username: "user",
                    notes: payload
                )
            }
        }
    }
}
