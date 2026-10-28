import AppKit
import Combine

/// Жизненный цикл приложения: сборка модулей, онбординг прав Accessibility,
/// запуск event tap, предупреждение о конфликтующих утилитах.
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var preferences: Preferences!
    private var layouts: LayoutController!
    private var converter: SystemLayoutConverter!
    private var engine: SwitcherEngine!
    private var eventTap: EventTapManager!
    private var appRules: AppRulesManager!
    private var menuBar: MenuBarController!
    private var settings: SettingsWindowController!
    private var diary: DiaryService!
    private var conflicts: ConflictDetector!
    private var notifications: NotificationService!
    private var license: LicenseService!
    private var sync: SyncService!
    private var stats: StatisticsService!
    private var personal: PersonalDictionary!
    private var hud: CorrectionHUD!
    private var hotKeys: HotKeyCenter!
    private var selection: SelectionConverter!
    private var onboarding: OnboardingWindowController?
    private var permissionPollTimer: Timer?
    private var subscriptions = Set<AnyCancellable>()

    public func applicationDidFinishLaunching(_ notification: Notification) {
        CrashGuard.install()
        preferences = Preferences()
        layouts = LayoutController()
        diary = DiaryService(preferences: preferences)
        conflicts = ConflictDetector()
        notifications = NotificationService(preferences: preferences)
        license = LicenseService()
        stats = StatisticsService()
        personal = PersonalDictionary()
        hud = CorrectionHUD()
        let updateService = UpdateService(preferences: preferences)
        let importExport = ImportExportService(preferences: preferences)
        settings = SettingsWindowController(
            preferences: preferences,
            diary: diary,
            importExport: importExport,
            updates: updateService,
            notifications: notifications,
            license: license,
            stats: stats,
            personal: personal
        )

        // Pro-функции (синхронизация, автозамена) — по лицензии (раздел 22).
        preferences.proUnlocked = license.proFeaturesUnlocked
        license.onChange = { [weak self] in
            guard let self else { return }
            self.preferences.proUnlocked = self.license.proFeaturesUnlocked
        }

        // Таблицы раскладок — по реально установленным input sources.
        converter = SystemLayoutConverter()
        converter.rebuild(sources: layouts.sourcesForConversion())
        layouts.onSourcesChanged = { [weak self] in
            guard let self else { return }
            self.converter.rebuild(sources: self.layouts.sourcesForConversion())
        }

        // «Мозг»: статистический детектор на словарях и триграммной модели.
        // Ресурсы прогреваются в фоне, чтобы не задерживать старт.
        let dictionaries = DictionaryService()
        let ngrams = NGramModel()
        DispatchQueue.global(qos: .utility).async {
            dictionaries.warmUp()
            ngrams.warmUp()
        }

        appRules = AppRulesManager(preferences: preferences)
        eventTap = EventTapManager()
        let replacer = TextReplacer()
        replacer.gate = eventTap.gate
        let prefs = preferences!
        engine = SwitcherEngine(
            detector: StatisticalDetector(
                dictionaries: dictionaries,
                ngrams: ngrams,
                converter: converter,
                personal: personal,
                enabledLayouts: { prefs.engine.detectionLanguages }
            ),
            buffer: InputBuffer(isMappable: { [converter] ch in converter?.isMappable(ch) ?? false }),
            layouts: layouts,
            replacer: replacer,
            appRules: appRules,
            wordRules: WordRulesManager(preferences: preferences),
            preferences: preferences,
            focus: FocusInspector(),
            converter: converter,
            personal: personal,
            diary: diary,
            expander: TextExpander(preferences: preferences),
            stats: stats
        )
        appRules.onActivate = { [weak self] in
            self?.engine.handle(.contextLost)
        }

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
                if self.preferences.hudEnabled {
                    self.hud.show(layout.displayName)
                }
                self.notifications.notifyCorrection(to: layout)
                self.menuBar.refresh()
            }
        }

        updateService.onUpdateAvailable = { [weak self] version, url in
            self?.menuBar.showUpdateAvailable(version: version, url: url)
        }
        updateService.checkInBackgroundIfDue()

        sync = SyncService(preferences: preferences, importExport: importExport)
        preferences.$syncEnabled
            .combineLatest(preferences.$proUnlocked)
            .map { $0 && $1 }
            .removeDuplicates()
            .sink { [weak self] enabled in self?.sync.setEnabled(enabled) }
            .store(in: &subscriptions)

        hotKeys = HotKeyCenter()
        selection = SelectionConverter(converter: converter, layouts: layouts, stats: stats)
        preferences.$selectionHotkeysEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in self?.configureSelectionHotkeys(enabled) }
            .store(in: &subscriptions)

        eventTap.handler = { [engine] event in
            engine?.handle(event)
        }
        eventTap.enterInterceptor = { [engine] flags in
            engine?.interceptEnter(flags: flags) ?? false
        }
        preferences.$reliableMode
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] intercept in self?.eventTap.restart(interceptEnter: intercept) }
            .store(in: &subscriptions)

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
        guard eventTap.start(interceptEnter: preferences.reliableMode) else {
            menuBar.setPermissionWarningVisible(true)
            Log.app.error("Event tap не запустился при имеющихся правах")
            return
        }
        menuBar.refresh()
    }

    /// Горячие клавиши для выделенного текста: ⌃⌥K / ⌃⌥U / ⌃⌥T.
    private func configureSelectionHotkeys(_ enabled: Bool) {
        hotKeys.unregisterAll()
        guard enabled else { return }
        // Виртуальные коды ANSI: K = 40, U = 32, T = 17.
        hotKeys.register(.controlOption(40)) { [weak self] in self?.runSelection(.layout) }
        hotKeys.register(.controlOption(32)) { [weak self] in self?.runSelection(.invertCase) }
        hotKeys.register(.controlOption(17)) { [weak self] in self?.runSelection(.transliterate) }
    }

    private func runSelection(_ transform: SelectionConverter.Transform) {
        guard preferences.enabled,
              appRules.frontmostMode() != .off,
              PermissionsManager.isTrusted else { return }
        selection.perform(transform)
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
