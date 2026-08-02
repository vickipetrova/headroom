import Foundation
import Testing

@testable import HeadroomCore

/// Only `Credentials.token(in:)`, which is pure `Data -> String?`.
///
/// Every token below is a made-up string. Nothing here reads the credentials file or the Keychain:
/// `accessToken()`, `tokenFromFile()`, and `tokenFromKeychain()` all reach the developer's real
/// login, and `#expect` prints compared values into CI logs on failure — so a test that touched a
/// live token would print it there.
@Suite struct CredentialsTests {
    private func token(_ string: String) throws -> String? {
        Credentials.token(in: try #require(string.data(using: .utf8)))
    }

    @Test func readsTheTokenFromClaudeCodesJSON() throws {
        let json = #"{"claudeAiOauth": {"accessToken": "fake-token-value", "expiresAt": 123}}"#
        #expect(try token(json) == "fake-token-value")
    }

    @Test func ignoresTheOtherFieldsAlongsideIt() throws {
        let json = #"""
        {"claudeAiOauth": {"refreshToken": "fake-refresh", "accessToken": "fake-access",
         "scopes": ["user:inference"], "subscriptionType": "max"}, "trustedDeviceToken": "fake-device"}
        """#
        #expect(try token(json) == "fake-access")
    }

    /// Hand-made setups sometimes store the bare token instead of the JSON envelope.
    @Test func acceptsABareToken() throws {
        #expect(try token("fake-bare-token") == "fake-bare-token")
    }

    @Test func trimsSurroundingWhitespace() throws {
        #expect(try token("  fake-bare-token\n") == "fake-bare-token")
    }

    /// The `hasPrefix("{")` guard earns its keep here: without it, JSON that failed the structured
    /// parse would be handed back whole and sent as a bearer token.
    @Test(arguments: [
        #"{"claudeAiOauth": {}}"#,
        #"{"claudeAiOauth": {"accessToken": ""}}"#,
        #"{"claudeAiOauth": {"accessToken": 42}}"#,
        #"{"someOtherApp": {"accessToken": "fake"}}"#,
        #"{"claudeAiOauth": "not-an-object"}"#,
        #"{"unclosed": "#,
    ])
    func refusesJSONThatDoesNotCarryAToken(_ json: String) throws {
        #expect(try token(json) == nil)
    }

    @Test(arguments: ["", "   ", "\n\t "])
    func refusesEmptyInput(_ string: String) throws {
        #expect(try token(string) == nil)
    }

    @Test func refusesBytesThatAreNotText() {
        #expect(Credentials.token(in: Data([0xFF, 0xFE, 0x00, 0x80])) == nil)
    }
}
