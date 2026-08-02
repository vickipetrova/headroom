import Foundation
import UserNotifications

/// Threshold alerts: at most one per window per reset period.
///
/// "Per reset period" is the important part. Polling every minute at 85% with an 80% threshold
/// must not produce an alert every minute, and quitting and relaunching must not restart the
/// count — so the marker is the window's own reset timestamp, persisted.
enum Notifier {
    private static let defaults = UserDefaults.standard

    /// Asked once, at launch. macOS remembers the answer; calling again is a no-op.
    static func requestAuthorizationIfNeeded() {
        guard Settings.notifyThreshold > 0 else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func evaluate(_ windows: [LimitWindow]) {
        let threshold = Settings.notifyThreshold
        guard threshold > 0 else { return }

        for window in windows where window.utilization >= Double(threshold) {
            let key = "notified.\(window.label)"
            // The threshold is part of the marker: lowering it mid-window is a new crossing the
            // user just asked to hear about, not a repeat of one they already saw.
            let marker = "\(window.resetsAt?.timeIntervalSince1970 ?? 0)|\(threshold)"
            guard defaults.string(forKey: key) != marker else { continue }
            defaults.set(marker, forKey: key)
            post(window, threshold: threshold)
        }
    }

    private static func post(_ window: LimitWindow, threshold: Int) {
        let content = UNMutableNotificationContent()
        content.title = "\(window.shortLabel) at \(Fmt.pct(window.utilization))"
        content.body = window.resetsAt == nil
            ? "Past your \(threshold)% alert."
            : "Resets \(Fmt.clock(window.resetsAt)) — in \(Fmt.countdown(to: window.resetsAt))."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
