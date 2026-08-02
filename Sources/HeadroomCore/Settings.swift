import Foundation
import ServiceManagement

/// Preferences, backed by UserDefaults. There is no settings window in v0.1 — everything here is
/// driven from the Settings submenu in the dropdown.
enum Settings {
    /// Minutes between polls. The endpoint is cheap, but there's no reason to hammer it.
    static let refreshOptions = [1, 5, 15]

    /// Utilization percentage that triggers an alert. 0 means never.
    static let thresholdOptions = [0, 50, 80, 90]

    /// Reassigned only by tests, which point it at a scratch suite rather than the real preferences.
    static var defaults = UserDefaults.standard

    private enum Key {
        static let refreshMinutes = "refreshMinutes"
        static let notifyThreshold = "notifyThreshold"
        static let titleFormat = "titleFormat"
    }

    enum TitleFormat: Int, CaseIterable {
        case both = 0
        case sessionOnly = 1
        case weeklyOnly = 2
        case highest = 3

        var title: String {
            switch self {
            case .both: return "Session and Weekly"
            case .sessionOnly: return "Session Only"
            case .weeklyOnly: return "Weekly Only"
            case .highest: return "Highest Usage"
            }
        }
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

    static var titleFormat: TitleFormat {
        get {
            guard defaults.object(forKey: Key.titleFormat) != nil else { return .both }
            let stored = defaults.integer(forKey: Key.titleFormat)
            return TitleFormat(rawValue: stored) ?? .both
        }
        set { defaults.set(newValue.rawValue, forKey: Key.titleFormat) }
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
