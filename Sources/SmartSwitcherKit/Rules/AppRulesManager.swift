import AppKit

/// Правила приложений (FR-5): авто / только вручную / выключено.
///
/// `NSWorkspace.frontmostApplication` корректно читается только на главном
/// потоке, а движок спрашивает режим с фоновой очереди. Поэтому bundle id
/// активного приложения кешируется по уведомлению `didActivateApplication`
/// и читается из кеша потокобезопасно.
public final class AppRulesManager {
    private let preferences: Preferences
    private let lock = NSLock()
    private var cachedFrontmostBundleID: String?

    /// Активировано другое приложение — контекст набора потерян.
    public var onActivate: (() -> Void)?

    public init(preferences: Preferences) {
        self.preferences = preferences
        cachedFrontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    /// Режим для активного приложения. Потокобезопасно.
    public func frontmostMode() -> AppMode {
        preferences.engine.mode(forBundleID: frontmostBundleID())
    }

    public func frontmostBundleID() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return cachedFrontmostBundleID
    }

    @objc private func appActivated(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        let bundleID = app?.bundleIdentifier ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        lock.lock()
        cachedFrontmostBundleID = bundleID
        lock.unlock()
        onActivate?()
    }
}
