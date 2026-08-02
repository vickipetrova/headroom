import Foundation
import Security

/// Finds the OAuth token Claude Code already holds, so Headroom needs no setup of its own.
///
/// Nothing in this file logs, prints, caches, or persists the token. It is read on demand,
/// handed to a single request, and dropped. Keep it that way — see the guardrails in CLAUDE.md.
enum Credentials {
    private static let credentialsPath = "~/.claude/.credentials.json"

    /// Claude Code writes the same JSON blob under this service name in the login Keychain.
    private static let keychainService = "Claude Code-credentials"

    /// The current access token, or nil if Claude Code has never signed in on this Mac.
    ///
    /// Read fresh on every call rather than cached: Claude Code rotates this token during
    /// active sessions, and a cached copy would go stale and start 401ing.
    static func accessToken() -> String? {
        tokenFromFile() ?? tokenFromKeychain()
    }

    // MARK: - Sources

    private static func tokenFromFile() -> String? {
        let path = (credentialsPath as NSString).expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return token(in: data)
    }

    private static func tokenFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return token(in: data)
    }

    // MARK: - Parsing

    /// The Keychain item and the file both hold `{"claudeAiOauth": {"accessToken": "..."}}`.
    /// Older and hand-made setups sometimes store the bare token instead, so fall back to
    /// treating the payload as the token itself.
    private static func token(in data: Data) -> String? {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let oauth = object["claudeAiOauth"] as? [String: Any],
           let token = oauth["accessToken"] as? String,
           !token.isEmpty {
            return token
        }
        guard let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty, !raw.hasPrefix("{")
        else { return nil }
        return raw
    }
}
