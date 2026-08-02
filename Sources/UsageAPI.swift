import Foundation

// MARK: - Provider-neutral model

/// One rate-limit window, described in terms no single vendor owns.
///
/// `label` is whatever the provider wants shown as that window's heading, so a future provider
/// can say "TODAY" or "THIS MONTH" without MenuController learning anything about it.
struct LimitWindow {
    enum Kind {
        /// The short rolling window (Claude Code: 5 hours).
        case session
        /// The long window, across everything.
        case weekly
        /// The long window, narrowed to one model. A provider may report several.
        case weeklyScoped
    }

    let kind: Kind
    /// Heading for this window in the dropdown, e.g. "THIS WEEK (all models)".
    let label: String
    /// Sentence-case form for notifications, e.g. "This week".
    let shortLabel: String
    /// Percent of the window consumed, 0–100.
    let utilization: Double
    let resetsAt: Date?
}

/// A source of usage windows. `ClaudeProvider` is the only implementation in v0.1; the protocol
/// exists so Cursor/Codex/Copilot providers can be added without MenuController changing.
protocol UsageProvider {
    var name: String { get }
    func fetch(completion: @escaping (Result<[LimitWindow], Error>) -> Void)
}

enum UsageError: LocalizedError {
    case noCredentials
    case unauthorized
    case http(Int)
    case network(Error)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .noCredentials:
            return "No Claude Code login found. Open Claude Code once to sign in."
        case .unauthorized:
            return "Token expired — open a Claude Code session to refresh it."
        case .http(let code):
            return "Usage API returned HTTP \(code)."
        case .network:
            return "Can't reach api.anthropic.com."
        case .badResponse:
            return "Couldn't read the usage response."
        }
    }
}

// MARK: - Claude

struct ClaudeProvider: UsageProvider {
    let name = "Claude"

    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    /// Ephemeral: no on-disk cache of usage responses, and no chance of serving a stale one.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    func fetch(completion: @escaping (Result<[LimitWindow], Error>) -> Void) {
        guard let token = Credentials.accessToken() else {
            completion(.failure(UsageError.noCredentials))
            return
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        Self.session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(UsageError.network(error)))
                return
            }
            guard let http = response as? HTTPURLResponse, let data else {
                completion(.failure(UsageError.badResponse))
                return
            }
            guard http.statusCode == 200 else {
                completion(.failure(http.statusCode == 401
                    ? UsageError.unauthorized
                    : UsageError.http(http.statusCode)))
                return
            }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(UsageError.badResponse))
                return
            }
            completion(.success(Self.windows(in: object)))
        }.resume()
    }

    // MARK: - Parsing
    //
    // This endpoint is undocumented and community-discovered: it has already grown a second,
    // richer shape alongside the original one, and it will drift again. Every field here is
    // treated as optional and every type as a guess. A field that is missing, null, or the wrong
    // type drops that one row — it never throws and never crashes.

    static func windows(in object: [String: Any]) -> [LimitWindow] {
        var session: LimitWindow?
        var weekly: LimitWindow?
        var scoped: [LimitWindow] = []

        // Preferred shape: a `limits` array, which generalizes the old Opus-specific weekly key
        // into `weekly_scoped` entries that name their own model.
        for entry in (object["limits"] as? [[String: Any]]) ?? [] {
            guard let kind = entry["kind"] as? String,
                  let utilization = number(entry["percent"])
            else { continue }
            let resetsAt = date(entry["resets_at"])

            switch kind {
            case "session":
                session = LimitWindow(kind: .session, label: sessionLabel, shortLabel: sessionShort,
                                      utilization: utilization, resetsAt: resetsAt)
            case "weekly_all":
                weekly = LimitWindow(kind: .weekly, label: weeklyLabel, shortLabel: weeklyShort,
                                     utilization: utilization, resetsAt: resetsAt)
            case "weekly_scoped":
                let model = ((entry["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String
                scoped.append(scopedWindow(model: model ?? "scoped",
                                           utilization: utilization, resetsAt: resetsAt))
            default:
                continue  // A kind we don't know yet. Ignoring it beats guessing at a label.
            }
        }

        // Original shape, still returned alongside the array. Used to fill anything the array
        // didn't provide, so a rename on either side degrades to a missing row rather than a
        // blank app.
        if session == nil, let legacy = legacyWindow(object["five_hour"]) {
            session = LimitWindow(kind: .session, label: sessionLabel, shortLabel: sessionShort,
                                  utilization: legacy.utilization, resetsAt: legacy.resetsAt)
        }
        if weekly == nil, let legacy = legacyWindow(object["seven_day"]) {
            weekly = LimitWindow(kind: .weekly, label: weeklyLabel, shortLabel: weeklyShort,
                                 utilization: legacy.utilization, resetsAt: legacy.resetsAt)
        }
        if scoped.isEmpty, let legacy = legacyWindow(object["seven_day_opus"]) {
            scoped.append(scopedWindow(model: "Opus",
                                       utilization: legacy.utilization, resetsAt: legacy.resetsAt))
        }

        return [session, weekly].compactMap { $0 } + scoped
    }

    private static let sessionLabel = "SESSION (5-hour window)"
    private static let sessionShort = "Session"
    private static let weeklyLabel = "THIS WEEK (all models)"
    private static let weeklyShort = "This week"

    private static func scopedWindow(model: String, utilization: Double,
                                     resetsAt: Date?) -> LimitWindow {
        LimitWindow(kind: .weeklyScoped,
                    label: "THIS WEEK (\(model))",
                    shortLabel: "This week (\(model))",
                    utilization: utilization, resetsAt: resetsAt)
    }

    private static func legacyWindow(_ any: Any?) -> (utilization: Double, resetsAt: Date?)? {
        guard let dict = any as? [String: Any],
              let utilization = number(dict["utilization"])
        else { return nil }
        return (utilization, date(dict["resets_at"]))
    }

    /// `percent` and `utilization` have both been seen as Int and as Double.
    private static func number(_ any: Any?) -> Double? {
        if let double = any as? Double { return double }
        if let int = any as? Int { return Double(int) }
        return nil
    }

    private static func date(_ any: Any?) -> Date? {
        if let seconds = any as? Double { return Date(timeIntervalSince1970: seconds) }
        guard let string = any as? String else { return nil }
        // Timestamps currently arrive as "2026-08-02T16:39:59.408408+00:00". The fractional-seconds
        // parser is required for those and returns nil without them, so both are needed.
        return fractionalISO.date(from: string) ?? plainISO.date(from: string)
    }

    private static let fractionalISO: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainISO: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
