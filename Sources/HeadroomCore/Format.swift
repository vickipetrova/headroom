import AppKit
import Foundation

/// Percentages, countdowns, clock times, and the colour ramp. Pure formatting — no state.
///
/// `now`, `locale`, and `timeZone` are parameters with live defaults rather than reads of global
/// state, so every function here is a pure function of its arguments and can be checked without
/// waiting for a clock or guessing at the machine's region.
enum Fmt {
    /// Anthropic's orange, used only for the spark glyph.
    static let spark = NSColor(srgbRed: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255, alpha: 1)

    /// Beyond this, a reset time needs a weekday to be unambiguous, and the countdown switches to
    /// days. Both must use the same comparison or the two rows contradict each other — at exactly
    /// 24h the menu used to read "Resets 9:00 AM — in 1d 0h".
    private static let dayThreshold: TimeInterval = 86_400

    static func pct(_ utilization: Double?) -> String {
        guard let utilization, utilization.isFinite else { return "–" }
        return "\(Int(utilization.rounded()))%"
    }

    /// "2h 13m" until the window resets. Days collapse to "2d 1h" — minute precision is noise
    /// at that distance.
    static func countdown(to date: Date?, from now: Date = Date()) -> String {
        guard let date else { return "unknown" }
        let interval = date.timeIntervalSince(now)
        // `Int(_: Double)` traps on a non-finite or out-of-range value, and the reset timestamp
        // comes from an endpoint we don't control.
        guard interval.isFinite, interval < Double(Int.max) else { return "unknown" }
        let seconds = Int(interval)
        if seconds <= 0 { return "now" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    /// Local wall-clock time, in the user's 12- or 24-hour preference. Resets a day or more out get a
    /// weekday, because "09:00" alone is ambiguous by then.
    static func clock(_ date: Date?, from now: Date = Date(),
                      locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        guard let date else { return "?" }
        let formatter = DateFormatter()
        // `setLocalizedDateFormatFromTemplate` resolves the pattern against whatever locale the
        // formatter holds when it is called, so these two assignments must stay above it.
        formatter.locale = locale
        formatter.timeZone = timeZone
        // Built per call rather than cached in a static: a menu bar app runs for weeks, and a cached
        // formatter keeps showing 12-hour time after the user switches the system to 24-hour. The
        // cost is a handful of allocations per menu open.
        formatter.setLocalizedDateFormatFromTemplate(
            date.timeIntervalSince(now) >= dayThreshold ? "EEE jmm" : "jmm")
        return formatter.string(from: date)
    }

    /// The one place this sentence is written. It used to exist separately in the dropdown and in
    /// notification bodies, and the two had already drifted — one carried a trailing full stop.
    static func resetLine(for date: Date?, from now: Date = Date()) -> String {
        guard date != nil else { return "Reset time unknown" }
        return "Resets \(clock(date, from: now)) — in \(countdown(to: date, from: now))"
    }

    static func color(_ utilization: Double) -> NSColor {
        switch utilization {
        case ..<50: return .systemGreen
        case ..<80: return .systemYellow
        default: return .systemRed
        }
    }
}
