import AppKit
import Foundation

/// Percentages, countdowns, clock times, and the colour ramp. Pure formatting — no state.
///
/// `now`, `locale`, and `timeZone` are parameters with live defaults rather than reads of global
/// state, so every function here is a pure function of its arguments and can be checked without
/// waiting for a clock or guessing at the machine's region.
enum Fmt {
    /// Anthropic's orange: the spark glyph in the menu bar, and the progress bars in the dropdown.
    ///
    /// Deliberately not the severity ramp below. The menu bar title is the at-a-glance signal and
    /// carries green/yellow/red; the panel carries identity, and a bar that turned red would be
    /// shouting the same thing twice.
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

    /// How long ago the numbers on screen were fetched: "just now", "5m ago", "2h ago".
    ///
    /// Deliberately vaguer than a clock time. Next to a Refresh command the useful question is "are
    /// these stale?", and "4m ago" answers it without the reader having to subtract.
    static func age(of date: Date?, from now: Date = Date()) -> String {
        guard let date else { return "never" }
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 45 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(max(minutes, 1))m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }

    /// The one place this sentence is written. It used to exist separately in the dropdown and in
    /// notification bodies, and the two had already drifted — one carried a trailing full stop.
    static func resetLine(for date: Date?, from now: Date = Date()) -> String {
        guard date != nil else { return "Reset time unknown" }
        return "Resets \(clock(date, from: now)) — in \(countdown(to: date, from: now))"
    }

    /// The spark for the menu bar, drawn as an image rather than set as a character in the title.
    ///
    /// In `.system` mode the image is a *template*: macOS then draws it in whatever colour a
    /// built-in menu bar control would use, which means it inverts correctly when the item is
    /// highlighted and follows the menu bar between light and dark. Coloured text does none of that.
    /// In `.alertsOnly` the glyph is baked in the brand orange and is not a template, so it keeps its
    /// colour — the same `isTemplate = (color == nil)` split the reference project uses.
    ///
    /// Rebuilt per render rather than cached: it is one small glyph a few times a minute, and a
    /// cache would have to be invalidated on both mode changes and appearance changes.
    static func sparkImage(mode: Settings.ColorMode) -> NSImage {
        let glyph = "✻" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: mode == .system ? NSColor.labelColor : spark,
        ]
        let size = glyph.size(withAttributes: attributes)
        let image = NSImage(size: NSSize(width: ceil(size.width), height: ceil(size.height)))
        image.lockFocus()
        glyph.draw(at: .zero, withAttributes: attributes)
        image.unlockFocus()
        image.isTemplate = mode == .system
        return image
    }

    /// Which surface is being coloured. The two differ only in the calm state, where the number
    /// takes the ordinary label colour and the bar takes the brand orange — one function can't serve
    /// both without being told which it is colouring.
    enum ColorRole {
        case title
        case bar
    }

    /// The single place utilization becomes a colour, for the menu bar title and the panel's bars
    /// alike, so the two can never disagree about what 80% looks like.
    static func color(_ utilization: Double,
                      mode: Settings.ColorMode,
                      role: ColorRole) -> NSColor {
        // `.system` ignores utilization entirely. That is not a missing branch — "fully monochrome"
        // means the thresholds don't apply, so the menu bar item looks like every other one up there.
        guard mode == .alertsOnly else {
            return role == .title ? .labelColor : .secondaryLabelColor
        }
        switch utilization {
        case ..<50: return role == .title ? .labelColor : spark
        case ..<80: return .systemYellow
        default: return .systemRed
        }
    }
}
