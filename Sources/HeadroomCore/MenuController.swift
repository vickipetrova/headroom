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

    /// Rows whose text contains a countdown, so they can be refreshed in place while the menu
    /// sits open. Rebuilt with the menu.
    private var countdownRows: [(item: NSMenuItem, text: () -> String)] = []

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
    }

    /// Keeps whatever was last shown. A dead network or an expired token shouldn't blank out
    /// numbers that were true a few minutes ago; the menu says so instead.
    func update(error: Error) {
        self.lastError = error
        renderTitle()
    }

    /// Refreshes countdowns without rebuilding the menu, for the case where it's held open.
    func tick() {
        guard isMenuOpen else { return }  // Closed menus rebuild from scratch on the way open.
        for row in countdownRows { row.item.title = row.text() }
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
        menu.removeAllItems()
        countdownRows.removeAll()

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
                menu.addItem(row("\(Fmt.pct(window.utilization)) used"))
                menu.addItem(countdownRow(for: window))
            }
            menu.addItem(.separator())
            // The error line already carries the timestamp ("Showing data from 14:02"), so an
            // Updated row alongside it would say the same thing twice.
            if let lastError {
                menu.addItem(row(message(for: lastError)))
            } else if let lastUpdated {
                menu.addItem(row("Updated \(Fmt.clock(lastUpdated))"))
            }
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

    private func countdownRow(for window: LimitWindow) -> NSMenuItem {
        let text = {
            guard window.resetsAt != nil else { return "Reset time unknown" }
            return "Resets \(Fmt.clock(window.resetsAt)) — in \(Fmt.countdown(to: window.resetsAt))"
        }
        let item = row(text())
        countdownRows.append((item, text))
        return item
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
