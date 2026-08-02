import Foundation
import Testing

@testable import HeadroomCore

/// Everything between the socket and the parser. No network: `ClaudeProvider.result` is pure, and
/// `fetch` is never called from a test — it would use the developer's real token.
@Suite struct TransportTests {
    private let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private func response(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
    }

    private func data(_ json: String) throws -> Data {
        try #require(json.data(using: .utf8))
    }

    private func error(from result: Result<[LimitWindow], Error>) -> UsageError? {
        guard case .failure(let failure) = result else { return nil }
        return failure as? UsageError
    }

    @Test func aGoodResponseParsesToWindows() throws {
        let body = try data(#"{"limits": [{"kind": "session", "percent": 42}]}"#)
        let result = ClaudeProvider.result(data: body, response: response(200), error: nil)
        #expect(try result.get().map(\.utilization) == [42])
    }

    /// 401 is the one status with bespoke advice, because it's the one the user can act on.
    @Test func unauthorizedGetsItsOwnMessage() throws {
        let result = ClaudeProvider.result(data: try data("{}"), response: response(401), error: nil)
        #expect(error(from: result) == .unauthorized)
        #expect(error(from: result)?.errorDescription?.contains("Token expired") == true)
    }

    /// Every other non-200 reports its code rather than guessing at a cause. A redirect lands here
    /// too, since the session refuses to follow them.
    @Test(arguments: [301, 302, 307, 400, 403, 429, 500, 503])
    func otherStatusesSurfaceTheirCode(_ status: Int) throws {
        let result = ClaudeProvider.result(data: try data("{}"), response: response(status), error: nil)
        #expect(error(from: result) == .http(status))
        #expect(error(from: result)?.errorDescription?.contains("\(status)") == true)
    }

    @Test func aTransportFailureIsReportedAsNetwork() {
        let dropped = URLError(.notConnectedToInternet)
        let result = ClaudeProvider.result(data: nil, response: nil, error: dropped)
        #expect(error(from: result) == .network(dropped))
        #expect(error(from: result)?.errorDescription?.contains("api.anthropic.com") == true)
    }

    /// A transport error wins even if a partial response came back with it.
    @Test func aTransportFailureOutranksAnyResponse() throws {
        let result = ClaudeProvider.result(data: try data("{}"), response: response(200),
                                           error: URLError(.timedOut))
        #expect(error(from: result) == .network(URLError(.timedOut)))
    }

    @Test func aMissingBodyIsABadResponse() {
        #expect(error(from: ClaudeProvider.result(data: nil, response: response(200), error: nil))
            == .badResponse)
    }

    @Test func aNonHTTPResponseIsABadResponse() throws {
        let plain = URLResponse(url: url, mimeType: nil,
                                expectedContentLength: 0, textEncodingName: nil)
        #expect(error(from: ClaudeProvider.result(data: try data("{}"), response: plain, error: nil))
            == .badResponse)
    }

    /// A JSON *array* root, an error envelope that isn't an object, or plain HTML from a proxy.
    @Test(arguments: ["[]", #"["nope"]"#, "null", "42", "<html>maintenance</html>", ""])
    func aRootThatIsNotAnObjectIsABadResponse(_ body: String) throws {
        #expect(error(from: ClaudeProvider.result(data: try data(body),
                                                  response: response(200), error: nil))
            == .badResponse)
    }

    /// 200 with a well-formed object that simply has no limits is success with nothing to show —
    /// the API-key-account case — not an error.
    @Test func anEmptyObjectIsSuccessWithNoWindows() throws {
        let result = ClaudeProvider.result(data: try data("{}"), response: response(200), error: nil)
        #expect(try result.get().isEmpty)
    }
}

extension UsageError: @retroactive Equatable {
    /// Test-only, and deliberately compares `network` by URLError code rather than by identity —
    /// `Error` isn't `Equatable`, and the code is the part these tests care about.
    public static func == (lhs: UsageError, rhs: UsageError) -> Bool {
        switch (lhs, rhs) {
        case (.noCredentials, .noCredentials),
             (.credentialsAccessDenied, .credentialsAccessDenied),
             (.unauthorized, .unauthorized),
             (.badResponse, .badResponse):
            return true
        case (.http(let a), .http(let b)):
            return a == b
        case (.network(let a), .network(let b)):
            return (a as? URLError)?.code == (b as? URLError)?.code
        default:
            return false
        }
    }
}
