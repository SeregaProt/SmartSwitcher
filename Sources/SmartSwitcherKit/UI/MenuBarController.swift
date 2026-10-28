import AppKit

/// Иконка и меню в строке меню (FR-9).
public final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let preferences: Preferences
    private let layouts: LayoutController
    private let updates: UpdateService

    public var openSettings: (() -> Void)?

    private let toggleItem = NSMenuItem()
    private let layoutInfoItem = NSMenuItem()
    private let permissionItem = NSMenuItem()
    private let conflictItem = NSMenuItem()
    private let updateAvailableItem = NSMenuItem()
    private var updateURL: URL?

    public init(preferences: Preferences, layouts: LayoutController, updates: UpdateService) {
        self.preferences = preferences
        self.layouts = layouts
        self.updates = updates
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        buildMenu()
        refresh()

        // Обновление иконки при смене раскладки любым способом.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceChanged),
            name: NSNotification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
            object: nil
        )
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    private func buildMenu() {
        let menu = NSMenu()

        toggleItem.target = self
        toggleItem.action = #selector(toggleEnabled)
        menu.addItem(toggleItem)

        let pauseItem = NSMenuItem(
            title: L10n.text("menu.pause10", "Приостановить на 10 минут"),
            action: #selector(pauseTenMinutes),
            keyEquivalent: ""
        )
        pauseItem.target = self
        menu.addItem(pauseItem)

        menu.addItem(.separator())

        layoutInfoItem.isEnabled = false
        menu.addItem(layoutInfoItem)

        permissionItem.title = L10n.text("menu.permission", "⚠️ Нет доступа Universal Access — открыть настройки")
        permissionItem.target = self
        permissionItem.action = #selector(openAccessibilitySettings)
        permissionItem.isHidden = true
        menu.addItem(permissionItem)

        conflictItem.title = L10n.text("menu.conflict", "⚠️ Обнаружена другая утилита перехвата клавиатуры")
        conflictItem.isEnabled = false
        conflictItem.isHidden = true
        menu.addItem(conflictItem)

        updateAvailableItem.target = self
        updateAvailableItem.action = #selector(openUpdate)
        updateAvailableItem.isHidden = true
        menu.addItem(updateAvailableItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: L10n.text("menu.settings", "Настройки…"),
            action: #selector(openSettingsWindow),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let updatesItem = NSMenuItem(
            title: L10n.text("menu.updates", "Проверить обновления…"),
            action: #selector(checkUpdates),
            keyEquivalent: ""
        )
        updatesItem.target = self
        menu.addItem(updatesItem)

        let aboutItem = NSMenuItem(
            title: L10n.text("menu.about", "О программе SmartSwitcher"),
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: L10n.text("menu.quit", "Выход"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    public func refresh() {
        let layoutText = layouts.current()?.displayName ?? "⌨"
        statusItem.button?.title = layoutText
        statusItem.button?.appearsDisabled = !preferences.isActive
        toggleItem.title = preferences.isActive
            ? L10n.text("menu.pause", "Пауза")
            : L10n.text("menu.enable", "Включить")
        let layoutName = layouts.current()?.displayName
            ?? L10n.text("menu.layout.unknown", "не определена")
        layoutInfoItem.title = String(
            format: L10n.text("menu.layout", "Раскладка: %@"),
            layoutName
        )
    }

    public func setPermissionWarningVisible(_ visible: Bool) {
        permissionItem.isHidden = !visible
        if visible {
            statusItem.button?.title = "⚠️"
        } else {
            refresh()
        }
    }

    public func setConflictWarningVisible(_ visible: Bool) {
        conflictItem.isHidden = !visible
    }

    public func showUpdateAvailable(version: String, url: URL) {
        updateURL = url
        updateAvailableItem.title = String(
            format: L10n.text("menu.update.available", "⬆︎ Доступна версия %@ — открыть"),
            version
        )
        updateAvailableItem.isHidden = false
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        if preferences.isActive {
            preferences.enabled = false
        } else {
            preferences.enabled = true
            preferences.pausedUntil = nil
        }
        refresh()
    }

    @objc private func pauseTenMinutes() {
        preferences.pausedUntil = Date().addingTimeInterval(600)
        refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 601) { [weak self] in
            self?.refresh()
        }
    }

    @objc private func openSettingsWindow() {
        openSettings?()
    }

    @objc private func checkUpdates() {
        updates.check { [weak self] result in
            let alert = NSAlert()
            switch result {
            case .upToDate:
                alert.messageText = L10n.text("settings.updates.uptodate", "У вас последняя версия.")
            case let .available(version, url):
                self?.showUpdateAvailable(version: version, url: url)
                alert.messageText = String(format: L10n.text("settings.updates.available", "Доступна версия %@."), version)
                alert.addButton(withTitle: L10n.text("settings.updates.open", "Открыть страницу релиза"))
                alert.addButton(withTitle: L10n.text("common.later", "Позже"))
                NSApp.activate(ignoringOtherApps: true)
                if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(url) }
                return
            case .failed:
                alert.messageText = L10n.text("settings.updates.failed", "Не удалось проверить обновления.")
            }
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func openUpdate() {
        if let updateURL { NSWorkspace.shared.open(updateURL) }
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func openAccessibilitySettings() {
        PermissionsManager.openSystemSettings()
    }

    @objc private func inputSourceChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.refresh()
        }
    }
}
