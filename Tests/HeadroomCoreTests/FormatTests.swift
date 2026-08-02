import Foundation
import Testing

@testable import HeadroomCore

/// Formatting. Every function takes `now` (and `clock` takes a locale and time zone) so these are
/// pure functions of their arguments — no waiting on a clock, no dependence on the machine's region.
@Suite struct FormatTests {
    private let now = Date(timeIntervalSince1970: 0)
    private func offset(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

    // MARK: - Percentages

    @Test func percentageOfNothingIsADash() {
        #expect(Fmt.pct(nil) == "–")
    }

    @Test(arguments: [(0.0, "0%"), (3.0, "3%"), (49.4, "49%"), (49.5, "50%"),
                      (79.6, "80%"), (100.0, "100%")])
    func percentageRoundsToNearest(_ value: Double, _ expected: String) {
        #expect(Fmt.pct(value) == expected)
    }

    /// `Int(_: Double)` traps on a non-finite value. The parser clamps before this is reached, but
    /// the guard here means a future caller can't reintroduce the crash.
    @Test func percentageSurvivesNonFiniteInput() {
        #expect(Fmt.pct(.nan) == "–")
        #expect(Fmt.pct(.infinity) == "–")
    }

    // MARK: - Countdowns

    @Test func countdownToNothingIsUnknown() {
        #expect(Fmt.countdown(to: nil, from: now) == "unknown")
    }

    /// The full boundary table. Several of these are surprising (+1 second reads "0m"), which is
    /// exactly why they're pinned.
    @Test(arguments: [
        (-86_400.0, "now"), (-1.0, "now"), (0.0, "now"), (0.9, "now"),
        (1.0, "0m"), (59.0, "0m"), (60.0, "1m"), (3_599.0, "59m"),
        (3_600.0, "1h 0m"), (3_661.0, "1h 1m"), (86_399.0, "23h 59m"),
        (86_400.0, "1d 0h"), (86_401.0, "1d 0h"), (90_000.0, "1d 1h"),
        (604_800.0, "7d 0h"),
    ])
    func countdownBoundaries(_ seconds: TimeInterval, _ expected: String) {
        #expect(Fmt.countdown(to: offset(seconds), from: now) == expected)
    }

    @Test func countdownSurvivesAnAbsurdDate() {
        #expect(Fmt.countdown(to: .distantFuture, from: now) != "")
        #expect(Fmt.countdown(to: Date(timeIntervalSince1970: .infinity), from: now) == "unknown")
    }

    // MARK: - Age of the data

    /// Shown next to Refresh Now, so it answers "are these numbers stale?" rather than "what time
    /// was it?". Under a minute reads as "just now" rather than "0m ago", which would look broken.
    @Test(arguments: [
        (0.0, "just now"), (44.0, "just now"), (45.0, "1m ago"), (59.0, "1m ago"),
        (60.0, "1m ago"), (301.0, "5m ago"), (3_599.0, "59m ago"),
        (3_600.0, "1h ago"), (86_399.0, "23h ago"), (86_400.0, "1d ago"), (200_000.0, "2d ago"),
    ])
    func ageReadsAsElapsedTime(_ elapsed: TimeInterval, _ expected: String) {
        #expect(Fmt.age(of: offset(-elapsed), from: now) == expected)
    }

    @Test func ageOfNothingIsNever() {
        #expect(Fmt.age(of: nil, from: now) == "never")
    }

    /// A clock that jumps backwards (NTP correction, timezone change) must not produce a negative
    /// age or a crash.
    @Test func aFutureTimestampDoesNotGoNegative() {
        #expect(Fmt.age(of: offset(3_600), from: now) == "just now")
    }

    // MARK: - Clock times

    @Test func clockOfNothingIsAQuestionMark() {
        #expect(Fmt.clock(nil, from: now) == "?")
    }

    private let utc = TimeZone(identifier: "UTC")!

    /// 24-hour locales give a stable exact string. Note the deliberate absence of an `en_US`
    /// equality assertion: since ICU 72 the separator before AM/PM is U+202F (narrow no-break
    /// space), so a typed "5:40 PM" would not match while looking identical in the failure output.
    @Test(arguments: ["en_GB", "de_DE", "fr_FR"])
    func clockUsesTwentyFourHourTimeWhereTheLocaleDoes(_ identifier: String) {
        let time = Fmt.clock(offset(63_000), from: now,
                             locale: Locale(identifier: identifier), timeZone: utc)
        #expect(time == "17:30")
    }

    @Test func clockUsesTwelveHourTimeWhereTheLocaleDoes() {
        let time = Fmt.clock(offset(63_000), from: now,
                             locale: Locale(identifier: "en_US"), timeZone: utc)
        #expect(time.hasPrefix("5:30"))
        #expect(time.contains("PM"))
    }

    @Test func clockRespectsTheTimeZone() {
        let berlin = try? #require(TimeZone(identifier: "Europe/Berlin"))
        let time = Fmt.clock(offset(63_000), from: now,
                             locale: Locale(identifier: "en_GB"), timeZone: berlin ?? utc)
        #expect(time == "18:30")  // UTC+1 in January
    }

    /// Regression: `countdown` switched to days at 86 400 while `clock` added the weekday only
    /// *above* it, so at exactly 24 hours the menu read "Resets 9:00 AM — in 1d 0h" — the ambiguity
    /// the weekday exists to remove.
    @Test func clockAndCountdownAgreeOnWhereADayBegins() {
        let gb = Locale(identifier: "en_GB")
        let boundary = offset(86_400)

        // The same instant rendered twice, differing only in how far away it is. Comparing two
        // *different* instants would pass whichever branch ran, since their times differ anyway.
        let asNearby = Fmt.clock(boundary, from: boundary, locale: gb, timeZone: utc)
        let atBoundary = Fmt.clock(boundary, from: now, locale: gb, timeZone: utc)

        #expect(Fmt.countdown(to: boundary, from: now) == "1d 0h")  // countdown says days
        #expect(atBoundary != asNearby)                             // so clock must say weekday
        #expect(atBoundary.hasSuffix(asNearby))
    }

    /// Locale-agnostic invariant: the weekday form is the bare form with something in front. Holds
    /// wherever `EEE` leads, and fails loudly if the two-branch logic is ever collapsed.
    @Test(arguments: ["en_GB", "de_DE", "en_US", "ja_JP"])
    func weekdayFormExtendsTheBareForm(_ identifier: String) {
        let locale = Locale(identifier: identifier)
        let near = offset(3_600)
        let far = offset(3_600 + 86_400 * 2)
        let bare = Fmt.clock(near, from: now, locale: locale, timeZone: utc)
        let withWeekday = Fmt.clock(far, from: now, locale: locale, timeZone: utc)
        #expect(withWeekday.hasSuffix(bare))
        #expect(withWeekday.count > bare.count)
    }

    // MARK: - Colour ramp

    /// Asserted relationally rather than against `NSColor` identity: what the README promises is
    /// where the bands change, not which catalogue colour each one is.
    @Test func colourRampChangesAtFiftyAndEighty() {
        #expect(Fmt.color(0) == Fmt.color(49.9))
        #expect(Fmt.color(50) != Fmt.color(49.9))
        #expect(Fmt.color(50) == Fmt.color(79.9))
        #expect(Fmt.color(80) != Fmt.color(79.9))
        #expect(Fmt.color(80) == Fmt.color(100))
    }
}
