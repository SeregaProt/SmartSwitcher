import AppKit

/// Жизненный цикл приложения: сборка модулей, онбординг прав Accessibility,
/// запуск event tap, предупреждение о конфликтующих утилитах.
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var preferences: Preferences!
    private var layouts: LayoutController!
    private var engine: SwitcherEngine!
    private var eventTap: EventTapManager!
    private var menuBar: MenuBarController!
    private var settings: SettingsWindowController!
    private var diary: DiaryService!
    private var conflicts: ConflictDetector!
    private var notifications: NotificationService!
    private var license: LicenseService!
    private var sync: SyncService!
    private var onboarding: OnboardingWindowController?
    private var permissionPollTimer: Timer?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        CrashGuard.install()
        preferences = Preferences()
        layouts = LayoutController()
        diary = DiaryService(preferences: preferences)
        conflicts = ConflictDetector()
        notifications = NotificationService(preferences: preferences)
        license = LicenseService()
        let updateService = UpdateService(preferences: preferences)
        settings = SettingsWindowController(
            preferences: preferences,
            diary: diary,
            importExport: ImportExportService(preferences: preferences),
            updates: updateService,
            notifications: notifications,
            license: license
        )

        // «Мозг»: статистический детектор на словарях и биграммных моделях.
        // Ресурсы прогреваются в фоне, чтобы не задерживать старт.
        let dictionaries = DictionaryService()
        let ngrams = NGramModel()
        DispatchQueue.global(qos: .utility).async {
            dictionaries.warmUp()
            ngrams.warmUp()
        }

        let prefs = preferences!
        engine = SwitcherEngine(
            detector: StatisticalDetector(
                dictionaries: dictionaries,
                ngrams: ngrams,
                enabledLayouts: {
                    Set(prefs.detectionLanguages.compactMap(Layout.init(rawValue:)))
                }
            ),
            buffer: InputBuffer(),
            layouts: layouts,
            replacer: TextReplacer(),
            exclusions: AppExclusionManager(preferences: preferences),
            wordRules: WordRulesManager(preferences: preferences),
            preferences: preferences,
            focus: FocusInspector(),
            diary: diary,
            expander: TextExpander(preferences: preferences)
        )

        menuBar = MenuBarController(
            preferences: preferences,
            layouts: layouts,
            updates: updateService
        )
        menuBar.openSettings = { [weak self] in
            self?.settings.show()
        }

        engine.onCorrection = { [weak self] layout in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.preferences.soundEnabled {
                    NSSound(named: "Pop")?.play()
                }
                self.notifications.notifyCorrection(to: layout)
                self.menuBar.refresh()
            }
        }

        if preferences.autoCheckUpdates {
            updateService.checkInBackgroundIfDue()
        }

        sync = SyncService(
            preferences: preferences,
            importExport: ImportExportService(preferences: preferences)
        )
        sync.start()

        eventTap = EventTapManager()
        eventTap.handler = { [engine] event in
            engine?.handle(event)
        }

        // Первый запуск — пошаговый мастер (4.4); иначе старт/ожидание прав.
        if !preferences.onboardingCompleted {
            showOnboarding()
        } else if PermissionsManager.isTrusted {
            startEngine()
        } else {
            awaitPermission()
        }

        checkForConflicts()
        Log.app.info("SmartSwitcher запущен")
    }

    public func applicationWillTerminate(_ notification: Notification) {
        eventTap?.stop()
    }

    // MARK: - Запуск

    private func startEngine() {
        menuBar.setPermissionWarningVisible(false)
        guard eventTap.start() else {
            menuBar.setPermissionWarningVisible(true)
            Log.app.error("Event tap не запустился при имеющихся правах")
            return
        }
        menuBar.refresh()
    }

    /// Раздел 21 ТЗ: предупреждаем о других активных перехватчиках клавиатуры.
    private func checkForConflicts() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let competing = self.conflicts.competingKeyboardTaps()
            if competing > 0 {
                Log.app.warning("Обнаружено конкурирующих keyboard event tap: \(competing)")
            }
            DispatchQueue.main.async {
                self.menuBar.setConflictWarningVisible(competing > 0)
            }
        }
    }

    // MARK: - Онбординг (раздел 4.4 ТЗ)

    private func showOnboarding() {
        menuBar.setPermissionWarningVisible(!PermissionsManager.isTrusted)
        onboarding = OnboardingWindowController(preferences: preferences) { [weak self] in
            guard let self else { return }
            if PermissionsManager.isTrusted {
                self.startEngine()
            } else {
                self.awaitPermission()
            }
        }
        onboarding?.show()
    }

    /// Тихое ожидание выдачи прав без модального мастера (онбординг уже пройден).
    private func awaitPermission() {
        menuBar.setPermissionWarningVisible(true)
        permissionPollTimer?.invalidate()
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard PermissionsManager.isTrusted else { return }
            timer.invalidate()
            self?.permissionPollTimer = nil
            self?.startEngine()
            Log.app.info("Права Accessibility получены, движок запущен")
        }
    }
}
