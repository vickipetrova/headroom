import AppKit
import Foundation
import Testing

@testable import HeadroomCore

/// The dropdown's view model. `UsageRow` is a pure function of a `LimitWindow` and a clock, which is
/// what makes the panel testable at all — the views themselves need a running app, and
/// `MenuController` can't be constructed in a test (it creates a real status item).
@Suite struct UsagePanelTests {
    private let now = Date(timeIntervalSince1970: 1_785_600_000)

    private func window(_ utilization: Double, resetsIn seconds: TimeInterval?) -> LimitWindow {
        LimitWindow(kind: .session, id: "session", label: "SESSION · 5-HOUR", shortLabel: "Session", optionLabel: "opt",
                    utilization: utilization,
                    resetsAt: seconds.map { now.addingTimeInterval($0) })
    }

    @Test func splitsTheResetTimeBetweenHeadingAndValueLine() {
        let row = UsageRow(window(5, resetsIn: 15_300), now: now, mode: .alertsOnly)
        #expect(row.header == "SESSION · 5-HOUR")
        #expect(row.value == "5%")
        #expect(row.trailing == "resets in 4h 15m")
        // The wall-clock time sits on the heading line; only its presence is asserted here, since
        // its formatting is the locale-dependent part and `FormatTests` covers that.
        #expect(!row.headerTrailing.isEmpty)
    }

    /// A window whose reset time the endpoint didn't give still renders — it just says so.
    @Test func aMissingResetTimeDegradesInBothPlaces() {
        let row = UsageRow(window(42, resetsIn: nil), now: now, mode: .alertsOnly)
        #expect(row.headerTrailing.isEmpty)
        #expect(row.trailing == "reset time unknown")
        #expect(row.value == "42%")
    }

    @Test(arguments: [(0.0, 0.0), (12.5, 0.125), (50.0, 0.5), (99.9, 0.999), (100.0, 1.0)])
    func fractionTracksUtilization(_ utilization: Double, _ expected: Double) {
        #expect(abs(UsageRow(window(utilization, resetsIn: 60), now: now, mode: .alertsOnly).fraction - expected) < 0.0001)
    }

    /// `Capsule` happily draws past its frame, so the bar clamps rather than trusting its input —
    /// the parser bounds utilization to 0–100, but a bar that can overflow its track is a rendering
    /// bug waiting for the one payload that gets through.
    @Test(arguments: [(-40.0, 0.0), (150.0, 1.0), (100.0001, 1.0)])
    func fractionIsClampedToTheTrack(_ utilization: Double, _ expected: Double) {
        #expect(UsageRow(window(utilization, resetsIn: 60), now: now, mode: .alertsOnly).fraction == expected)
    }

    /// `min`/`max` propagate NaN, so clamping alone doesn't catch it — a NaN would reach SwiftUI as
    /// an invalid frame width and the bar would silently vanish. `ClaudeProvider` can't produce one,
    /// but this is the view model for any future provider.
    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func fractionSurvivesNonFiniteUtilization(_ utilization: Double) {
        let fraction = UsageRow(window(utilization, resetsIn: 60), now: now, mode: .alertsOnly).fraction
        #expect(fraction.isFinite)
        #expect((0...1).contains(fraction))
    }

    /// The percentage in the panel must agree with the one in the menu bar title, which rounds.
    @Test func percentageMatchesTheMenuBarTitle() {
        let row = UsageRow(window(79.6, resetsIn: 60), now: now, mode: .alertsOnly)
        #expect(row.value == "80%")
        #expect(row.value == Fmt.pct(79.6))
    }

    @Test func headingComesStraightFromTheWindowLabel() {
        let scoped = LimitWindow(kind: .weeklyScoped, id: "scoped:Fable",
                                 label: "THIS WEEK · FABLE", shortLabel: "This week (Fable)", optionLabel: "opt",
                                 utilization: 16, resetsAt: now.addingTimeInterval(3_600))
        #expect(UsageRow(scoped, now: now, mode: .alertsOnly).header == "THIS WEEK · FABLE")
    }

    /// The bar's colour is resolved in the view model, so it is covered by the same tests as the
    /// menu bar title rather than only being visible on screen.
    @Test func barColourFollowsTheMode() {
        #expect(UsageRow(window(20, resetsIn: 60), now: now, mode: .alertsOnly).barColor == Fmt.spark)
        #expect(UsageRow(window(85, resetsIn: 60), now: now, mode: .alertsOnly).barColor == .systemRed)
        // System mode is monochrome at every level, including one that would be red otherwise.
        #expect(UsageRow(window(20, resetsIn: 60), now: now, mode: .system).barColor
            == .secondaryLabelColor)
        #expect(UsageRow(window(85, resetsIn: 60), now: now, mode: .system).barColor
            == .secondaryLabelColor)
    }

    /// One sentence, used both as the VoiceOver label and as the menu item's `title` — the latter
    /// being what AppleScript reports, since a view-backed item draws no title of its own. Derived
    /// in one place so the two can't describe the same row differently.
    @Test func theSpokenFormCarriesTheWholeRow() {
        let spoken = UsageRow(window(5, resetsIn: 15_300), now: now, mode: .alertsOnly).spoken
        #expect(spoken.contains("SESSION · 5-HOUR"))
        #expect(spoken.contains("5%"))
        #expect(spoken.contains("resets in 4h 15m"))
    }
}

/// Which limits the menu bar title renders. Separate suite because these are the rules that are
/// awkward to reach by hand — a scope vanishing from the response, or all of them vanishing at once.
@Suite struct TitleSelectionTests {
    private func window(_ kind: LimitWindow.Kind, _ id: String) -> LimitWindow {
        LimitWindow(kind: kind, id: id, label: id, shortLabel: id, optionLabel: "opt",
                    utilization: 10, resetsAt: nil)
    }

    private var all: [LimitWindow] {
        [window(.session, LimitWindow.sessionID),
         window(.weekly, LimitWindow.weeklyID),
         window(.weeklyScoped, "scoped:Fable")]
    }

    @Test func rendersOnlyTheSelectedLimits() {
        let shown = TitleSelection.windows(from: all, selection: [LimitWindow.sessionID])
        #expect(shown.map(\.id) == [LimitWindow.sessionID])
    }

    /// Order comes from the response, not from the order the user ticked boxes in.
    @Test func keepsResponseOrderRegardlessOfSelection() {
        let shown = TitleSelection.windows(
            from: all, selection: ["scoped:Fable", LimitWindow.sessionID, LimitWindow.weeklyID])
        #expect(shown.map(\.id) == [LimitWindow.sessionID, LimitWindow.weeklyID, "scoped:Fable"])
    }

    /// A scope the user picked that the response no longer reports is simply not rendered — no gap,
    /// no placeholder, and the stored preference is left alone elsewhere so it returns if it does.
    @Test func aVanishedScopeIsDroppedFromTheTitle() {
        let shown = TitleSelection.windows(
            from: all, selection: [LimitWindow.sessionID, "scoped:GoneAway"])
        #expect(shown.map(\.id) == [LimitWindow.sessionID])
    }

    /// Every selection missing must not render an empty title — a bare spark reads as broken and
    /// gives no route back to the setting that caused it.
    @Test func everySelectionMissingFallsBackToSession() {
        let shown = TitleSelection.windows(from: all, selection: ["scoped:GoneAway", "alsoGone"])
        #expect(shown.map(\.id) == [LimitWindow.sessionID])
    }

    /// …and if even the session window is absent, show whatever came first rather than nothing.
    @Test func withoutASessionWindowItFallsBackToTheFirstReported() {
        let weeklyOnly = [window(.weekly, LimitWindow.weeklyID)]
        #expect(TitleSelection.windows(from: weeklyOnly, selection: ["nothing"]).map(\.id)
            == [LimitWindow.weeklyID])
    }

    @Test func nothingReportedRendersNothing() {
        #expect(TitleSelection.windows(from: [], selection: [LimitWindow.sessionID]).isEmpty)
    }
}
