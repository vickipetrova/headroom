import AppKit
import SwiftUI

// The dropdown's informational rows.
//
// They are SwiftUI views inside `NSMenuItem.view` rather than ordinary menu items because an
// ordinary item that isn't a command has to be disabled, and macOS draws disabled items greyed out —
// which is what made the whole panel look washed out. AppKit does not dim a custom view, so these
// render at full strength while `NSMenu` still provides the material background, the dismissal
// behaviour, and key equivalents for the real commands below them.

/// Everything one usage section displays, derived from a `LimitWindow`.
///
/// Pure, so the formatting and the bar arithmetic are unit-testable without standing up any AppKit
/// object — `MenuController` cannot be constructed in a test (it creates a real status item), and CI
/// enforces that.
struct UsageRow {
    /// "SESSION · 5-HOUR"
    let header: String
    /// The wall-clock reset time, right of the header. Empty when the endpoint didn't give one.
    let headerTrailing: String
    /// "42%"
    let value: String
    /// "resets in 4h 15m"
    let trailing: String
    /// 0...1, for the bar.
    let fraction: Double

    /// Resolved here rather than in the view, so the bar's colour is covered by the same tests as
    /// the menu bar title's and the two can't drift apart.
    let barColor: NSColor

    /// The whole row as one sentence, for VoiceOver and for the menu item's `title` — which is what
    /// AppleScript reports, since a view-backed item draws no title of its own. Derived here so the
    /// two can't drift into describing the same row differently.
    var spoken: String { "\(header), \(value) used, \(trailing)" }

    /// `mode` has no default on purpose. It used to default to `Settings.colorMode`, which made the
    /// type read a global while its own doc claimed purity — and because Swift evaluates default
    /// arguments at the call site, passing it explicitly changed nothing. Callers name it now.
    init(_ window: LimitWindow, now: Date = Date(), mode: Settings.ColorMode) {
        barColor = Fmt.color(window.utilization, mode: mode, role: .bar)
        header = window.label
        headerTrailing = window.resetsAt.map { Fmt.clock($0, from: now) } ?? ""
        value = Fmt.pct(window.utilization)
        trailing = window.resetsAt == nil
            ? "reset time unknown"
            : "resets in \(Fmt.countdown(to: window.resetsAt, from: now))"
        // Clamped rather than trusted. `ClaudeProvider` already bounds utilization to 0–100, but
        // this is the view model for *any* `UsageProvider` — the roadmap invites more — and a bar
        // that can overflow its track is a rendering bug waiting for the one payload that gets
        // through. The finite check is not redundant with the clamp: `min`/`max` propagate NaN, so
        // a NaN would reach SwiftUI as an invalid frame width and the bar would simply vanish.
        fraction = window.utilization.isFinite ? min(max(window.utilization / 100, 0), 1) : 0
    }
}

struct UsageRowView: View {
    let row: UsageRow

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // `.callout` rather than `.caption` throughout the small text: caption is 10pt on macOS,
            // which is genuinely hard to read for something you glance at. The heading additionally
            // takes semibold and the full label colour — at secondary it read as disabled, which is
            // the exact impression this panel was redesigned to shed.
            HStack(spacing: 8) {
                Text(row.header)
                    .font(.callout.weight(.semibold))
                Spacer(minLength: 8)
                Text(row.headerTrailing)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.value)
                    .font(.system(size: 15, weight: .semibold))
                    // Monospaced digits for the same reason the menu bar title uses them: the number
                    // must not shuffle sideways as it ticks over.
                    .monospacedDigit()
                Spacer(minLength: 8)
                Text(row.trailing)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ProgressBar(fraction: row.fraction, color: row.barColor)
        }
        .padding(.horizontal, PanelMetrics.horizontalPadding)
        .padding(.vertical, 7)
        .frame(minWidth: PanelMetrics.minimumWidth, maxWidth: .infinity, alignment: .leading)
        // The row is decoration, not a control: it should never be read as an eleven-part list, and
        // the bar has no meaning to announce beyond the percentage already in `value`.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.spoken)
    }
}

private struct ProgressBar: View {
    let fraction: Double
    let color: NSColor

    var body: some View {
        // GeometryReader rather than a fixed inner width, so the fill tracks the panel width if
        // PanelMetrics ever changes.
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(nsColor: .quaternaryLabelColor))
                Capsule()
                    .fill(Color(nsColor: color))
                    .frame(width: max(0, geometry.size.width * fraction))
            }
        }
        .frame(height: PanelMetrics.barHeight)
    }
}

/// The footer, and every message-only state: an error, "Loading…".
struct PanelTextView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)  // wrap instead of truncating
            // Bounded, or a long error line lays out at its natural width and drags the whole menu
            // wider than the usage rows. Deliberately *not* derived from `minimumWidth`: that is a
            // floor for a menu with nothing in it, and when the two were the same constant, lowering
            // the floor silently wrapped every error message into a narrow column with dead space
            // beside it.
            .frame(maxWidth: PanelMetrics.textWrapWidth, alignment: .leading)
            .padding(.horizontal, PanelMetrics.horizontalPadding)
            .padding(.vertical, 5)
            .frame(minWidth: PanelMetrics.minimumWidth, maxWidth: .infinity, alignment: .leading)
    }
}

enum PanelMetrics {
    /// A floor, not a target — see `NSMenuItem.hosting`. Only wide enough that a menu showing
    /// nothing but "Loading…" isn't a sliver; the usage rows are all wider than this on their own,
    /// so in practice the menu sizes to its content.
    ///
    /// It was 300 for no reason beyond being the number picked while building the panel, and since
    /// AppKit adds a constant 65pt of chrome that made every menu 365pt wide. Measured: the widest
    /// row wants 240pt naturally (the weekly heading plus its reset time), so the menu now settles
    /// at 305pt. Going below that means shortening the copy, not adjusting this.
    static let minimumWidth: CGFloat = 200
    static let horizontalPadding: CGFloat = 14
    static let barHeight: CGFloat = 4

    /// How wide message text is allowed to lay out before wrapping.
    ///
    /// Tracks the *measured* natural width of a usage row rather than `minimumWidth`, so a wrapped
    /// error line ends where the rows end instead of leaving a column of dead space under full-width
    /// separators.
    ///
    /// 258pt is what the widest row (the weekly heading plus its reset time) measures at the current
    /// type sizes — it was 240 before the small text moved from `.caption` to `.callout`. Any change
    /// to the row's fonts or copy moves this number; re-measure rather than guessing.
    static var textWrapWidth: CGFloat { 258 - horizontalPadding * 2 }
}

// MARK: - Hosting

extension NSMenuItem {
    /// Wraps a SwiftUI view in a menu item sized to fit.
    ///
    /// `title` is set even though a view-backed item never draws it: it is what the accessibility
    /// API and AppleScript report, which keeps `get name of every menu item` — this project's
    /// standing way to verify the menu, documented in CLAUDE.md — working.
    static func hosting<Content: View>(_ view: Content, title: String) -> (NSMenuItem, NSHostingView<Content>) {
        let hosting = NSHostingView(rootView: view)
        // Without an explicit size the item can lay out at zero height on first display.
        hosting.frame.size = hosting.fittingSize
        // AppKit sizes the menu from the widest item and then adds its own chrome — measured at 65pt
        // beyond a 300pt row — but it lays the view out at x=0 and does not stretch it. Left alone,
        // every one of those points became dead space on the right, so the separators visibly ran
        // past the end of the text. Autoresizing lets the row grow into the width the menu actually
        // chose; the SwiftUI frame's `minWidth` is what the menu measured in the first place.
        hosting.autoresizingMask = [.width]
        let item = NSMenuItem()
        item.title = title
        item.view = hosting
        // These rows are data, not commands. Left enabled — the default, since the menu sets
        // `autoenablesItems = false` — releasing the mouse over one selects it and dismisses the
        // whole menu, arrow-key navigation stops on rows that draw no highlight, and VoiceOver
        // offers them as actionable. Disabling costs nothing here: it dims an item's *own* drawing,
        // and this item draws none.
        item.isEnabled = false
        return (item, hosting)
    }
}
