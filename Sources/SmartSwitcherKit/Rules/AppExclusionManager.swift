import AppKit

/// Белый список приложений (FR-5): в исключённых приложениях
/// авто-исправление не работает.
///
/// `NSWorkspace.frontmostApplication` корректно читается только на главном
/// потоке, а движок спрашивает исключение с потока event tap. Поэтому bundle id
/// активного приложения кешируется по уведомлению `didActivateApplication`
/// и читается из кеша потокобезопасно.
public final class AppExclusionManager {
    private let preferences: Preferences
    private let lock = NSLock()
    private var cachedFrontmostBundleID: String?

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

    public func isFrontmostExcluded() -> Bool {
        guard let bundleID = frontmostBundleID() else { return false }
        return isExcluded(bundleID: bundleID)
    }

    public func frontmostBundleID() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return cachedFrontmostBundleID
    }

    public func isExcluded(bundleID: String) -> Bool {
        preferences.excludedApps.contains { excluded in
            bundleID == excluded || bundleID.hasPrefix(excluded + ".")
        }
    }

    @objc private func appActivated(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        let bundleID = app?.bundleIdentifier ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        lock.lock()
        cachedFrontmostBundleID = bundleID
        lock.unlock()
    }
}
