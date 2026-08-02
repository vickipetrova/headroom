import AppKit

/// Wiring: a provider, a menu, and two timers.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let provider: UsageProvider = ClaudeProvider()
    private let menuController = MenuController()

    private var pollTimer: Timer?
    private var tickTimer: Timer?

    private let pollInterval: TimeInterval = 300

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)  // Menu bar only, no dock icon, no window.

        menuController.onRefresh = { [weak self] in self?.refresh() }

        refresh()
        pollTimer = schedule(every: pollInterval) { [weak self] in self?.refresh() }
        tickTimer = schedule(every: 60) { [weak self] in self?.menuController.tick() }

        // Timers are unreliable across sleep — the Mac can wake hours later with a window that
        // has already reset. Ask again the moment it wakes.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func didWake() { refresh() }

    private func refresh() {
        provider.fetch { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let windows):
                    self.menuController.update(windows: windows, updatedAt: Date())
                case .failure(let error):
                    self.menuController.update(error: error)
                }
            }
        }
    }

    /// `.common` mode matters: a timer in the default mode stops firing while a menu is open,
    /// which is exactly when the countdown refresh needs to run.
    private func schedule(every interval: TimeInterval, _ block: @escaping () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in block() }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
