import AppKit

/// Owns the status item: the title in the menu bar and the dropdown behind it.
///
/// Knows nothing about where usage comes from — it is handed `[LimitWindow]` and renders it.
final class MenuController: NSObject, NSMenuDelegate {
    /// Called when the user picks Refresh Now.
    var onRefresh: (() -> Void)?

    /// Called when a preference changes, so the poll timer can be rescheduled.
    var onSettingsChanged: (() -> Void)?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    private var windows: [LimitWindow] = []
    private var lastUpdated: Date?
    private var lastError: Error?
    private var isMenuOpen = false

    /// A row that can be rewritten in place while the menu sits open, so a menu held across a tick
    /// or a poll stays honest without being rebuilt underneath the user.
    ///
    /// `text` reads *current* state each time it is called rather than closing over a value — see
    /// `window(labelled:)`. It returns nil for "leave this row's text alone", which is what a row
    /// whose window has vanished from the latest poll does: one-poll-stale beats blanking the row
    /// or writing some other window's number into it.
    private struct LiveRow { let item: NSMenuItem; let text: () -> String? }

    /// Rebuilt with the menu, and cleared before it — these hold strong references to `NSMenuItem`s.
    private var liveRows: [LiveRow] = []

    override init() {
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        statusItem.button?.title = "✻ …"
    }

    // MARK: - Input

    func update(windows: [LimitWindow], updatedAt: Date) {
        self.windows = windows
        self.lastUpdated = updatedAt
        self.lastError = nil
        renderTitle()
        // A poll can land while the dropdown is open, and the open dropdown is not rebuilt. Without
        // this the rows keep rendering the state they were built from — most visibly a countdown
        // running down to the *previous* window's reset and pinning at "now".
        refreshLiveRows()
    }

    /// Keeps whatever was last shown. A dead network or an expired token shouldn't blank out
    /// numbers that were true a few minutes ago; the menu says so instead.
    func update(error: Error) {
        self.lastError = error
        renderTitle()
        // Same reason as above, and it is the footer that changes: "Updated 14:02" has to become
        // the error line while the menu is on screen, or the menu claims a refresh that failed.
        refreshLiveRows()
    }

    /// Refreshes the live rows without rebuilding the menu, for the case where it's held open.
    func tick() { refreshLiveRows() }

    // MARK: - In-place refresh
    //
    // Every live row recomputes together, from all three entry points (tick, poll, poll failure), so
    // the menu can never show a mix of fresh and stale values — a percentage from one poll above a
    // reset time from the one before it is worse than either alone.
    //
    // Accepted limit, and a deliberate one: this rewrites rows, it cannot add or remove them. If a
    // poll changes the menu's *shape* — a `weekly_scoped` model appears or disappears, the first
    // successful poll replaces "Loading…" — the new shape waits for the next open, because the
    // alternative is rebuilding a menu that is on screen (see `rebuild`). The menu bar title, which
    // is what the user reads without clicking, is correct the whole time.

    private func refreshLiveRows() {
        guard isMenuOpen else { return }  // Closed menus rebuild from scratch on the way open.
        // Hazard: `NSMenuItem.attributedTitle` takes precedence over `title`, silently and with no
        // compiler complaint if both are set. This works today only because `header(_:)` is the sole
        // builder that sets `attributedTitle` and every live row comes from `row(_:)`, which sets
        // `title`. Colourizing a percentage row with `Fmt.color`, as the menu bar title does, would
        // turn every assignment below into a no-op; such a row has to be refreshed by re-setting its
        // attributed string instead.
        for row in liveRows {
            guard let text = row.text() else { continue }
            row.item.title = text
        }
    }

    // MARK: - Menu bar title

    private func renderTitle() {
        guard let button = statusItem.button else { return }

        guard !windows.isEmpty else {
            button.attributedTitle = NSAttributedString()
            if lastError != nil { button.title = "✻ !" }
            // A clean fetch that reported nothing isn't an error and isn't still loading —
            // API-key accounts have no plan quota to report.
            else if lastUpdated != nil { button.title = "✻ –" }
            else { button.title = "✻ …" }
            return
        }

        let title = NSMutableAttributedString()
        title.append(NSAttributedString(string: "✻ ", attributes: [
            .foregroundColor: Fmt.spark,
            .font: NSFont.systemFont(ofSize: 13),
        ]))
        title.append(percentage(of: windows.first { $0.kind == .session }))
        title.append(NSAttributedString(string: " · ", attributes: [
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        title.append(percentage(of: windows.first { $0.kind == .weekly }))
        button.attributedTitle = title
    }

    private func percentage(of window: LimitWindow?) -> NSAttributedString {
        // Monospaced digits so the title doesn't shuffle sideways as the numbers tick over.
        NSAttributedString(string: Fmt.pct(window?.utilization), attributes: [
            .foregroundColor: window.map { Fmt.color($0.utilization) } ?? NSColor.secondaryLabelColor,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
        ])
    }

    // MARK: - Dropdown

    func menuNeedsUpdate(_ menu: NSMenu) { rebuild() }
    func menuWillOpen(_ menu: NSMenu) { isMenuOpen = true }
    func menuDidClose(_ menu: NSMenu) { isMenuOpen = false }

    private func rebuild() {
        // Never rebuild a menu that is on screen. `menuNeedsUpdate` is not just an "about to open"
        // callback: AppKit also runs it while matching key equivalents, and this menu claims ⌘R and
        // ⌘Q, so it can fire mid-tracking. Rebuilding then would (1) delete the parent item of an
        // open Settings submenu out from under it, (2) re-target a click already in flight — the
        // user presses on "Refresh Now" and releases on whatever now occupies that row, which at the
        // bottom of this menu is "Quit Headroom" — and (3) discard highlight and keyboard-navigation
        // state, dropping the user back to the top of the menu mid-arrow-key. Open menus are updated
        // in place by `refreshLiveRows` instead.
        guard !isMenuOpen else { return }

        // Before the items go, not after: these registrations hold the `NSMenuItem`s strongly, so a
        // stale entry would keep a detached item alive and go on ticking it forever for a menu that
        // no longer contains it.
        liveRows.removeAll()
        menu.removeAllItems()

        if windows.isEmpty {
            if let lastError {
                menu.addItem(row(message(for: lastError)))
            } else if lastUpdated != nil {
                menu.addItem(row("No plan limits reported for this account."))
                menu.addItem(row("Pro and Max plans have session and weekly windows;"))
                menu.addItem(row("metered API-key accounts have no quota to show."))
            } else {
                menu.addItem(row("Loading…"))
            }
        } else {
            for (index, window) in windows.enumerated() {
                if index > 0 { menu.addItem(.separator()) }
                menu.addItem(header(window.label))
                menu.addItem(percentRow(for: window))
                menu.addItem(resetRow(for: window))
            }
            menu.addItem(.separator())
            menu.addItem(footerRow())
        }

        if Settings.notifyThreshold > 0, Notifier.alertsBlocked {
            menu.addItem(.separator())
            let item = action("Alerts blocked — open Notification settings",
                              key: "", selector: #selector(openNotificationSettings))
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(action("Refresh Now", key: "r", selector: #selector(refreshClicked)))
        menu.addItem(settingsItem())
        menu.addItem(action("Quit Headroom", key: "q", selector: #selector(quitClicked)))
    }

    // MARK: - Settings submenu
    //
    // Rebuilt with the rest of the menu, so every checkmark is read fresh rather than cached —
    // launch-at-login in particular can be revoked in System Settings behind our back.

    private func settingsItem() -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        submenu.addItem(header("REFRESH EVERY"))
        for minutes in Settings.refreshOptions {
            let title = minutes == 1 ? "1 minute" : "\(minutes) minutes"
            let item = action(title, key: "", selector: #selector(setInterval(_:)))
            item.tag = minutes
            item.state = Settings.refreshMinutes == minutes ? .on : .off
            submenu.addItem(item)
        }

        submenu.addItem(.separator())
        submenu.addItem(header("NOTIFY ABOVE"))
        for threshold in Settings.thresholdOptions {
            let item = action(threshold == 0 ? "Off" : "\(threshold)%",
                              key: "", selector: #selector(setThreshold(_:)))
            item.tag = threshold
            item.state = Settings.notifyThreshold == threshold ? .on : .off
            submenu.addItem(item)
        }

        submenu.addItem(.separator())
        let launch = action("Launch at Login", key: "", selector: #selector(toggleLaunchAtLogin))
        launch.state = Settings.launchAtLogin ? .on : .off
        submenu.addItem(launch)

        let item = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        item.isEnabled = true
        item.submenu = submenu
        return item
    }

    @objc private func setInterval(_ sender: NSMenuItem) {
        Settings.refreshMinutes = sender.tag
        onSettingsChanged?()
    }

    @objc private func setThreshold(_ sender: NSMenuItem) {
        Settings.notifyThreshold = sender.tag
        onSettingsChanged?()
    }

    @objc private func toggleLaunchAtLogin() {
        Settings.launchAtLogin.toggle()
    }

    // MARK: - Live rows

    /// Builds a disabled row and registers it for in-place refresh. `text` is the row's contents at
    /// *any* moment, not just this one: it runs here to seed the item, and again on every tick and
    /// every poll.
    private func liveRow(_ text: @escaping () -> String?) -> NSMenuItem {
        let item = row(text() ?? "")
        liveRows.append(LiveRow(item: item, text: text))
        return item
    }

    private func percentRow(for window: LimitWindow) -> NSMenuItem {
        let label = window.label
        return liveRow { [weak self] in
            guard let window = self?.window(labelled: label) else { return nil }
            return "\(Fmt.pct(window.utilization)) used"
        }
    }

    private func resetRow(for window: LimitWindow) -> NSMenuItem {
        let label = window.label
        return liveRow { [weak self] in
            guard let window = self?.window(labelled: label) else { return nil }
            return Fmt.resetLine(for: window.resetsAt)
        }
    }

    /// One row for two states. The error copy already carries the timestamp ("Showing data from
    /// 14:02"), so an Updated row beside it would say the same thing twice.
    ///
    /// Only built in the branch where `windows` is non-empty, which is also the only way
    /// `lastUpdated` is set — so in practice one of the two branches below always has something to
    /// say, and the empty fallback is unreachable rather than a blank row anyone can see.
    private func footerRow() -> NSMenuItem {
        liveRow { [weak self] in
            guard let self else { return nil }
            if let lastError { return message(for: lastError) }
            if let lastUpdated { return "Updated \(Fmt.clock(lastUpdated))" }
            return nil
        }
    }

    /// The window this row was built for, as it stands in the *latest* poll.
    ///
    /// Looking it up beats closing over the `LimitWindow`: a captured value made a held-open menu go
    /// on counting down to the reset of a window the poll had already replaced, reach "now", and
    /// stay pinned there until the menu was closed and reopened.
    ///
    /// `label` is the identity, matching `Notifier.markerKey(for:)`, which keys its
    /// already-announced markers on exactly the same string — including the vendor-supplied model
    /// name that distinguishes two scoped weekly windows. Two windows sharing a label would have to
    /// be the same window for that dedupe to be correct, so it is the right key here too.
    private func window(labelled label: String) -> LimitWindow? {
        windows.first { $0.label == label }
    }

    /// The plan's error copy, plus the "you're looking at old numbers" note that only makes sense
    /// when there are numbers on screen to be old.
    private func message(for error: Error) -> String {
        let description = (error as? UsageError)?.errorDescription
            ?? error.localizedDescription
        guard !windows.isEmpty, let lastUpdated else { return description }
        return "\(description) Showing data from \(Fmt.clock(lastUpdated))."
    }

    // MARK: - Item builders

    private func header(_ text: String) -> NSMenuItem {
        let item = NSMenuItem()
        item.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        item.isEnabled = false
        return item
    }

    private func row(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, key: String, selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        item.isEnabled = true
        return item
    }

    @objc private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func refreshClicked() { onRefresh?() }
    @objc private func quitClicked() { NSApp.terminate(nil) }
}
