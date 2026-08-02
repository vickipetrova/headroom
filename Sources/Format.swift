import AppKit
import Foundation

/// Percentages, countdowns, clock times, and the colour ramp. Pure formatting — no state.
enum Fmt {
    /// Anthropic's orange, used only for the spark glyph.
    static let spark = NSColor(srgbRed: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255, alpha: 1)

    static func pct(_ utilization: Double?) -> String {
        guard let utilization else { return "–" }
        return "\(Int(utilization.rounded()))%"
    }

    /// "2h 13m" until the window resets. Days collapse to "2d 1h" — minute precision is noise
    /// at that distance.
    static func countdown(to date: Date?) -> String {
        guard let date else { return "unknown" }
        let seconds = Int(date.timeIntervalSinceNow)
        if seconds <= 0 { return "now" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    /// Local wall-clock time, in the user's 12- or 24-hour preference. Resets more than a day out
    /// get a weekday, because "09:00" alone is ambiguous by then.
    static func clock(_ date: Date?) -> String {
        guard let date else { return "?" }
        let formatter = date.timeIntervalSinceNow > 86_400 ? weekdayTime : timeOnly
        return formatter.string(from: date)
    }

    static func color(_ utilization: Double) -> NSColor {
        switch utilization {
        case ..<50: return .systemGreen
        case ..<80: return .systemYellow
        default: return .systemRed
        }
    }

    // `setLocalizedDateFormatFromTemplate` picks 13:45 or 1:45 PM per the user's region, which a
    // hardcoded "HH:mm" would get wrong for most of the world.
    private static let timeOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        return formatter
    }()

    private static let weekdayTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEE jmm")
        return formatter
    }()
}
