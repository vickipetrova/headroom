import Foundation
import ServiceManagement

/// Preferences, backed by UserDefaults. There is no settings window in v0.1 — everything here is
/// driven from the Settings submenu in the dropdown.
enum Settings {
    /// Minutes between polls. The endpoint is cheap, but there's no reason to hammer it.
    static let refreshOptions = [1, 5, 15]

    /// Utilization percentage that triggers an alert. 0 means never.
    static let thresholdOptions = [0, 50, 80, 90]

    /// How much colour the menu bar and the panel use.
    enum ColorMode: String, CaseIterable {
        /// Colour means "pay attention": ordinary label colour and the brand orange until usage is
        /// worth noticing, then yellow, then red. The default, because a permanent green at 3% used
        /// is noise — it says "fine" in the state you are in almost always.
        case alertsOnly
        /// No colour at all. Everything takes a system label colour and the spark becomes a template
        /// image, so the whole item adapts like a built-in menu bar control.
        case system

        var label: String {
            switch self {
            case .alertsOnly: return "Alerts only"
            case .system: return "System"
            }
        }
    }

    /// Reassigned only by tests, which point it at a scratch suite rather than the real preferences.
    static var defaults = UserDefaults.standard

    private enum Key {
        static let refreshMinutes = "refreshMinutes"
        static let notifyThreshold = "notifyThreshold"
        static let colorMode = "colorMode"
    }

    /// Same shape as the two above: a stored value we don't recognise falls back to the default
    /// rather than leaving the app in a mode that doesn't exist.
    static var colorMode: ColorMode {
        get {
            defaults.string(forKey: Key.colorMode).flatMap(ColorMode.init(rawValue:)) ?? .alertsOnly
        }
        set { defaults.set(newValue.rawValue, forKey: Key.colorMode) }
    }

    /// Values outside the offered set fall back to the default, so a hand-edited plist can't
    /// leave the app polling every 0 seconds.
    static var refreshMinutes: Int {
        get {
            let stored = defaults.integer(forKey: Key.refreshMinutes)
            return refreshOptions.contains(stored) ? stored : 5
        }
        set { defaults.set(newValue, forKey: Key.refreshMinutes) }
    }

    static var refreshInterval: TimeInterval { TimeInterval(refreshMinutes * 60) }

    static var notifyThreshold: Int {
        get {
            guard defaults.object(forKey: Key.notifyThreshold) != nil else { return 80 }
            let stored = defaults.integer(forKey: Key.notifyThreshold)
            return thresholdOptions.contains(stored) ? stored : 80
        }
        set { defaults.set(newValue, forKey: Key.notifyThreshold) }
    }

    /// Deliberately not mirrored into UserDefaults: macOS owns this state (the user can revoke it
    /// in System Settings › General › Login Items), so a local copy would go stale and lie.
    static var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Registration legitimately fails when the app runs from a temporary or
                // quarantined location. Since the getter reads the real status, the checkmark
                // simply doesn't move — which is the honest result, not a silent lie.
            }
        }
    }
}
