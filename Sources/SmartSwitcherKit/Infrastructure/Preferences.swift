import Foundation
import Combine

/// Режим работы в конкретном приложении (FR-5).
public enum AppMode: String, Codable, Sendable {
    /// Авто-исправление и ручные жесты.
    case auto
    /// Только ручное исправление (Double-Shift, хоткеи выделения).
    case manualOnly
    /// Приложение полностью игнорируется.
    case off
}

/// Неизменяемый снимок настроек для движка. Движок живёт на фоновой очереди,
/// а `@Published`-свойства меняются на главном потоке; чтение массивов и
/// словарей одновременно с записью — гонка данных. Поэтому движок читает
/// только этот снимок, который публикуется под блокировкой.
public struct EngineSettings: Sendable {
    public var enabled = true
    public var pausedUntil: Date?
    public var excludedApps: Set<String> = []
    public var manualOnlyApps: Set<String> = []
    public var neverCorrectWords: Set<String> = []
    public var alwaysCorrectWords: Set<String> = []
    public var doubleShiftFixEnabled = true
    public var singleShiftSwitchEnabled = false
    public var undoLastEnabled = true
    public var shiftGestureWindow: TimeInterval = 0.4
    public var textExpansionEnabled = true
    public var expansionRules: [String: String] = [:]
    public var detectionLanguages: Set<Layout> = Set(Layout.allCases)
    public var learnFromTyping = true
    public var backspaceUndoEnabled = false
    public var reliableMode = true
    public var proUnlocked = true
    public var diaryEnabled = false

    public init() {}

    /// Активно ли авто-исправление прямо сейчас (вкл. и не на паузе).
    public func isActive(at date: Date = Date()) -> Bool {
        guard enabled else { return false }
        if let pausedUntil, pausedUntil > date { return false }
        return true
    }

    /// Режим для приложения; префикс bundle id покрывает семейства
    /// (`com.jetbrains` → все IDE JetBrains).
    public func mode(forBundleID bundleID: String?) -> AppMode {
        guard let bundleID else { return .auto }
        func matches(_ list: Set<String>) -> Bool {
            list.contains { bundleID == $0 || bundleID.hasPrefix($0 + ".") }
        }
        if matches(excludedApps) { return .off }
        if matches(manualOnlyApps) { return .manualOnly }
        return .auto
    }

    /// Платная автозамена работает только с Pro (раздел 22).
    public var expansionAvailable: Bool { textExpansionEnabled && proUnlocked }
}

/// Настройки приложения поверх UserDefaults (раздел 3.2 ТЗ, Infrastructure).
/// Свойства меняются только на главном потоке; фоновый код читает `engine`.
///
/// `@unchecked Sendable`: `@Published`-свойства меняются только на главном
/// потоке (UI, `DispatchQueue.main`), с других потоков читается лишь `engine`,
/// защищённый `snapshotLock`.
public final class Preferences: ObservableObject, @unchecked Sendable {
    private enum Key {
        static let enabled = "enabled"
        static let soundEnabled = "soundEnabled"
        static let notificationsEnabled = "notificationsEnabled"
        static let pausedUntil = "pausedUntil"
        static let excludedApps = "excludedApps"
        static let manualOnlyApps = "manualOnlyApps"
        static let neverCorrectWords = "neverCorrectWords"
        static let alwaysCorrectWords = "alwaysCorrectWords"
        static let wordRuleAdded = "wordRuleAdded"
        static let wordRuleRemoved = "wordRuleRemoved"
        static let diaryEnabled = "diaryEnabled"
        static let legacyLearnedWords = "learnedWords"
        // Хоткеи (FR-4)
        static let doubleShiftFixEnabled = "doubleShiftFixEnabled"
        static let singleShiftSwitchEnabled = "singleShiftSwitchEnabled"
        static let undoLastEnabled = "undoLastEnabled"
        static let shiftGestureWindow = "shiftGestureWindow"
        static let backspaceUndoEnabled = "backspaceUndoEnabled"
        static let selectionHotkeysEnabled = "selectionHotkeysEnabled"
        // Автозамена (FR-7)
        static let textExpansionEnabled = "textExpansionEnabled"
        static let expansionRules = "expansionRules"
        // Детект
        static let detectionLanguages = "detectionLanguages"
        static let learnFromTyping = "learnFromTyping"
        static let reliableMode = "reliableMode"
        static let hudEnabled = "hudEnabled"
        // Обновления (14)
        static let updateChannel = "updateChannel"
        static let autoCheckUpdates = "autoCheckUpdates"
        static let onboardingCompleted = "onboardingCompleted"
        static let syncEnabled = "syncEnabled"
    }

    /// Приложения, где SmartSwitcher выключен полностью: менеджеры паролей.
    public static let defaultExcludedApps: [String] = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.apple.keychainaccess",
        "com.apple.Passwords",
    ]

    /// Приложения, где работает только ручное исправление: терминалы —
    /// авто-исправление команд опасно, но Double-Shift полезен.
    /// iTerm намеренно не в списке: пользователь хочет автопереключение в нём.
    public static let defaultManualOnlyApps: [String] = [
        "com.apple.Terminal",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "com.github.wez.wezterm",
    ]

    private let defaults: UserDefaults
    private let snapshotLock = NSLock()
    private var snapshot = EngineSettings()
    /// Правила слов применяются из синхронизации — не ставить им новые метки.
    private var isApplyingMerge = false

    /// Потокобезопасный снимок для движка.
    public var engine: EngineSettings {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        return snapshot
    }

    @Published public var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Key.enabled); publish() }
    }

    @Published public var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Key.soundEnabled) }
    }

    @Published public var pausedUntil: Date? {
        didSet { defaults.set(pausedUntil, forKey: Key.pausedUntil); publish() }
    }

    @Published public var excludedApps: [String] {
        didSet { defaults.set(excludedApps, forKey: Key.excludedApps); publish() }
    }

    @Published public var manualOnlyApps: [String] {
        didSet { defaults.set(manualOnlyApps, forKey: Key.manualOnlyApps); publish() }
    }

    /// Слова, которые никогда не исправляются: ручные + самообучение (FR-5, FR-6).
    @Published public var neverCorrectWords: [String] {
        didSet {
            stampWordChanges(kind: "never", old: oldValue, new: neverCorrectWords)
            defaults.set(neverCorrectWords, forKey: Key.neverCorrectWords)
            publish()
        }
    }

    /// Слова, которые исправляются всегда, минуя детектор (FR-5).
    @Published public var alwaysCorrectWords: [String] {
        didSet {
            stampWordChanges(kind: "always", old: oldValue, new: alwaysCorrectWords)
            defaults.set(alwaysCorrectWords, forKey: Key.alwaysCorrectWords)
            publish()
        }
    }

    /// Метки времени добавления/удаления правил слов (`"never:слово"` → Unix-время)
    /// для слияния при синхронизации (LWW-element-set).
    public private(set) var wordRuleAdded: [String: Double] {
        didSet { defaults.set(wordRuleAdded, forKey: Key.wordRuleAdded) }
    }

    public private(set) var wordRuleRemoved: [String: Double] {
        didSet { defaults.set(wordRuleRemoved, forKey: Key.wordRuleRemoved) }
    }

    /// Дневник исправлений (FR-11): выключен по умолчанию.
    @Published public var diaryEnabled: Bool {
        didSet { defaults.set(diaryEnabled, forKey: Key.diaryEnabled); publish() }
    }

    /// Ненавязчивые уведомления при исправлении (FR-8): выключены по умолчанию.
    @Published public var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled) }
    }

    // MARK: - Хоткеи (FR-4)

    /// Double-Shift исправляет последнее слово (вкл. по умолчанию).
    @Published public var doubleShiftFixEnabled: Bool {
        didSet { defaults.set(doubleShiftFixEnabled, forKey: Key.doubleShiftFixEnabled); publish() }
    }

    /// Single-Shift меняет раскладку (опционально, выкл. по умолчанию — FR-4).
    @Published public var singleShiftSwitchEnabled: Bool {
        didSet { defaults.set(singleShiftSwitchEnabled, forKey: Key.singleShiftSwitchEnabled); publish() }
    }

    /// Разрешить откат последнего авто-исправления через Double-Shift (FR-4).
    @Published public var undoLastEnabled: Bool {
        didSet { defaults.set(undoLastEnabled, forKey: Key.undoLastEnabled); publish() }
    }

    /// Окно двойного нажатия Shift, сек (0.2…0.6).
    @Published public var shiftGestureWindow: Double {
        didSet { defaults.set(shiftGestureWindow, forKey: Key.shiftGestureWindow); publish() }
    }

    /// Backspace сразу после авто-исправления откатывает его (выкл. по умолчанию:
    /// мешает стереть пробел, чтобы поставить запятую).
    @Published public var backspaceUndoEnabled: Bool {
        didSet { defaults.set(backspaceUndoEnabled, forKey: Key.backspaceUndoEnabled); publish() }
    }

    /// Глобальные хоткеи для выделенного текста (⌃⌥K / ⌃⌥U / ⌃⌥T).
    @Published public var selectionHotkeysEnabled: Bool {
        didSet { defaults.set(selectionHotkeysEnabled, forKey: Key.selectionHotkeysEnabled) }
    }

    // MARK: - Автозамена текста (FR-7)

    @Published public var textExpansionEnabled: Bool {
        didSet { defaults.set(textExpansionEnabled, forKey: Key.textExpansionEnabled); publish() }
    }

    /// Правила автозамены: сокращение → развёрнутый текст.
    @Published public var expansionRules: [String: String] {
        didSet { defaults.set(expansionRules, forKey: Key.expansionRules); publish() }
    }

    // MARK: - Детект

    /// Активные раскладки детекта (по умолчанию обе). Хранятся как rawValue.
    @Published public var detectionLanguages: [String] {
        didSet { defaults.set(detectionLanguages, forKey: Key.detectionLanguages); publish() }
    }

    /// Личный словарь из собственного набора (хеши слов, локально).
    @Published public var learnFromTyping: Bool {
        didSet { defaults.set(learnFromTyping, forKey: Key.learnFromTyping); publish() }
    }

    /// Надёжный режим (активный tap, вкл. по умолчанию — ADR-0008): ввод
    /// придерживается на время перенабора, слово перед Enter тоже исправляется.
    /// Выключение возвращает чистый listen-only (ADR-0001).
    @Published public var reliableMode: Bool {
        didSet { defaults.set(reliableMode, forKey: Key.reliableMode); publish() }
    }

    /// Индикатор раскладки у курсора при исправлении.
    @Published public var hudEnabled: Bool {
        didSet { defaults.set(hudEnabled, forKey: Key.hudEnabled) }
    }

    /// Доступны ли платные функции (выставляет LicenseService, не хранится).
    @Published public var proUnlocked = true {
        didSet { publish() }
    }

    // MARK: - Обновления (14)

    /// Канал обновлений: "stable" | "beta".
    @Published public var updateChannel: String {
        didSet { defaults.set(updateChannel, forKey: Key.updateChannel) }
    }

    @Published public var autoCheckUpdates: Bool {
        didSet { defaults.set(autoCheckUpdates, forKey: Key.autoCheckUpdates) }
    }

    /// Пройден ли первичный онбординг (раздел 4.4).
    @Published public var onboardingCompleted: Bool {
        didSet { defaults.set(onboardingCompleted, forKey: Key.onboardingCompleted) }
    }

    /// Синхронизация настроек через iCloud (раздел 15): выкл по умолчанию.
    @Published public var syncEnabled: Bool {
        didSet { defaults.set(syncEnabled, forKey: Key.syncEnabled) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.enabled: true,
            Key.soundEnabled: true,
            Key.notificationsEnabled: false,
            Key.diaryEnabled: false,
            Key.excludedApps: Self.defaultExcludedApps,
            Key.manualOnlyApps: Self.defaultManualOnlyApps,
            Key.neverCorrectWords: [String](),
            Key.alwaysCorrectWords: [String](),
            Key.doubleShiftFixEnabled: true,
            Key.singleShiftSwitchEnabled: false,
            Key.undoLastEnabled: true,
            Key.shiftGestureWindow: 0.4,
            Key.backspaceUndoEnabled: false,
            Key.selectionHotkeysEnabled: true,
            Key.textExpansionEnabled: true,
            Key.expansionRules: [String: String](),
            Key.detectionLanguages: ["en", "ru"],
            Key.learnFromTyping: true,
            Key.reliableMode: true,
            Key.hudEnabled: true,
            Key.updateChannel: "stable",
            Key.autoCheckUpdates: true,
            Key.onboardingCompleted: false,
            Key.syncEnabled: false,
        ])
        enabled = defaults.bool(forKey: Key.enabled)
        soundEnabled = defaults.bool(forKey: Key.soundEnabled)
        notificationsEnabled = defaults.bool(forKey: Key.notificationsEnabled)
        diaryEnabled = defaults.bool(forKey: Key.diaryEnabled)
        pausedUntil = defaults.object(forKey: Key.pausedUntil) as? Date
        excludedApps = defaults.stringArray(forKey: Key.excludedApps) ?? Self.defaultExcludedApps
        manualOnlyApps = defaults.stringArray(forKey: Key.manualOnlyApps) ?? Self.defaultManualOnlyApps
        alwaysCorrectWords = defaults.stringArray(forKey: Key.alwaysCorrectWords) ?? []
        wordRuleAdded = defaults.dictionary(forKey: Key.wordRuleAdded) as? [String: Double] ?? [:]
        wordRuleRemoved = defaults.dictionary(forKey: Key.wordRuleRemoved) as? [String: Double] ?? [:]
        doubleShiftFixEnabled = defaults.bool(forKey: Key.doubleShiftFixEnabled)
        singleShiftSwitchEnabled = defaults.bool(forKey: Key.singleShiftSwitchEnabled)
        undoLastEnabled = defaults.bool(forKey: Key.undoLastEnabled)
        shiftGestureWindow = defaults.double(forKey: Key.shiftGestureWindow)
        backspaceUndoEnabled = defaults.bool(forKey: Key.backspaceUndoEnabled)
        selectionHotkeysEnabled = defaults.bool(forKey: Key.selectionHotkeysEnabled)
        textExpansionEnabled = defaults.bool(forKey: Key.textExpansionEnabled)
        expansionRules = defaults.dictionary(forKey: Key.expansionRules) as? [String: String] ?? [:]
        detectionLanguages = defaults.stringArray(forKey: Key.detectionLanguages) ?? ["en", "ru"]
        learnFromTyping = defaults.bool(forKey: Key.learnFromTyping)
        reliableMode = defaults.bool(forKey: Key.reliableMode)
        hudEnabled = defaults.bool(forKey: Key.hudEnabled)
        updateChannel = defaults.string(forKey: Key.updateChannel) ?? "stable"
        autoCheckUpdates = defaults.bool(forKey: Key.autoCheckUpdates)
        onboardingCompleted = defaults.bool(forKey: Key.onboardingCompleted)
        syncEnabled = defaults.bool(forKey: Key.syncEnabled)
        // Миграция со старого ключа самообучения (v0.1).
        var never = defaults.stringArray(forKey: Key.neverCorrectWords) ?? []
        if let legacy = defaults.stringArray(forKey: Key.legacyLearnedWords), !legacy.isEmpty {
            never.append(contentsOf: legacy.filter { !never.contains($0) })
            defaults.removeObject(forKey: Key.legacyLearnedWords)
            defaults.set(never, forKey: Key.neverCorrectWords)
        }
        neverCorrectWords = never
        publish()
    }

    /// Активно ли авто-исправление прямо сейчас (вкл. и не на паузе).
    public var isActive: Bool {
        engine.isActive()
    }

    /// Применить списки слов, полученные слиянием при синхронизации,
    /// вместе с их метками (без простановки новых меток).
    public func applyMergedWordRules(
        never: [String],
        always: [String],
        added: [String: Double],
        removed: [String: Double]
    ) {
        isApplyingMerge = true
        defer { isApplyingMerge = false }
        wordRuleAdded = added
        wordRuleRemoved = removed
        if neverCorrectWords != never { neverCorrectWords = never }
        if alwaysCorrectWords != always { alwaysCorrectWords = always }
    }

    // MARK: - Private

    private func stampWordChanges(kind: String, old: [String], new: [String]) {
        guard !isApplyingMerge else { return }
        let now = Date().timeIntervalSince1970
        let oldSet = Set(old), newSet = Set(new)
        for word in newSet.subtracting(oldSet) { wordRuleAdded["\(kind):\(word)"] = now }
        for word in oldSet.subtracting(newSet) { wordRuleRemoved["\(kind):\(word)"] = now }
    }

    /// Пересобрать снимок для движка. Вызывается из didSet (главный поток).
    private func publish() {
        var s = EngineSettings()
        s.enabled = enabled
        s.pausedUntil = pausedUntil
        s.excludedApps = Set(excludedApps)
        s.manualOnlyApps = Set(manualOnlyApps)
        s.neverCorrectWords = Set(neverCorrectWords)
        s.alwaysCorrectWords = Set(alwaysCorrectWords)
        s.doubleShiftFixEnabled = doubleShiftFixEnabled
        s.singleShiftSwitchEnabled = singleShiftSwitchEnabled
        s.undoLastEnabled = undoLastEnabled
        s.shiftGestureWindow = shiftGestureWindow
        s.textExpansionEnabled = textExpansionEnabled
        s.expansionRules = expansionRules
        s.detectionLanguages = Set(detectionLanguages.compactMap(Layout.init(rawValue:)))
        s.learnFromTyping = learnFromTyping
        s.backspaceUndoEnabled = backspaceUndoEnabled
        s.reliableMode = reliableMode
        s.proUnlocked = proUnlocked
        s.diaryEnabled = diaryEnabled
        snapshotLock.lock()
        snapshot = s
        snapshotLock.unlock()
    }
}
