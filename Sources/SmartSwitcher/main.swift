import AppKit
import SmartSwitcherKit

// Точка входа выполняется на главном потоке.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // Агентское приложение: без иконки в Dock, только menu bar (FR-9).
    app.setActivationPolicy(.accessory)
    app.run()
}
