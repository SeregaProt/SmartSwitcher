import Foundation
import Combine

/// Настройки приложения поверх UserDefaults (раздел 3.2 ТЗ, Infrastructure).
public final class Preferences: ObservableObject {
    private enum Key {
        static let enabled = "enabled"
        static let soundEnabled = "soundEnabled"
        static let notificationsEnabled = "notificationsEnabled"
        static let pausedUntil = "pausedUntil"
        static let excludedApps = "excludedApps"
        static let neverCorrectWords = "neverCorrectWords"
        static let alwaysCorrectWords = "alwaysCorrectWords"
        static let diaryEnabled = "diaryEnabled"
        static let legacyLearnedWords = "learnedWords"
        // Хоткеи (FR-4)
        static let doubleShiftFixEnabled = "doubleShiftFixEnabled"
        static let singleShiftSwitchEnabled = "singleShiftSwitchEnabled"
        static let undoLastEnabled = "undoLastEnabled"
        static let shiftGestureWindow = "shiftGestureWindow"
        // Автозамена (FR-7)
        static let textExpansionEnabled = "textExpansionEnabled"
        static let expansionRules = "expansionRules"
        // Языки детекта
        static let detectionLanguages = "detectionLanguages"
        // Обновления (14)
        static let updateChannel = "updateChannel"
        static let autoCheckUpdates = "autoCheckUpdates"
        static let onboardingCompleted = "onboardingCompleted"
        static let syncEnabled = "syncEnabled"
    }

    /// Приложения, в которых авто-исправление выключено по умолчанию:
    /// терминалы, менеджеры паролей (FR-5).
    /// iTerm намеренно НЕ в списке: пользователь хочет автопереключение в нём.
    /// Штатный Terminal.app остаётся исключённым (команды в кириллице ломают ввод).
    public static let defaultExcludedApps: [String] = [
        "com.apple.Terminal",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "com.github.wez.wezterm",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.apple.keychainaccess",
        "com.apple.Passwords",
    ]

    private let defaults: UserDefaults

    @Published public var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Key.enabled) }
    }

    @Published public var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Key.soundEnabled) }
    }

    @Published public var pausedUntil: Date? {
        didSet { defaults.set(pausedUntil, forKey: Key.pausedUntil) }
    }

    @Published public var excludedApps: [String] {
        didSet { defaults.set(excludedApps, forKey: Key.excludedApps) }
    }

    /// Слова, которые никогда не исправляются: ручные + самообучение (FR-5, FR-6).
    @Published public var neverCorrectWords: [String] {
        didSet { defaults.set(neverCorrectWords, forKey: Key.neverCorrectWords) }
    }

    /// Слова, которые исправляются всегда, минуя детектор (FR-5).
    @Published public var alwaysCorrectWords: [String] {
        didSet { defaults.set(alwaysCorrectWords, forKey: Key.alwaysCorrectWords) }
    }

    /// Дневник исправлений (FR-11): выключен по умолчанию.
    @Published public var diaryEnabled: Bool {
        didSet { defaults.set(diaryEnabled, forKey: Key.diaryEnabled) }
    }

    /// Ненавязчивые уведомления при исправлении (FR-8): выключены по умолчанию.
    @Published public var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled) }
    }

    // MARK: - Хоткеи (FR-4)

    /// Double-Shift исправляет последнее слово (вкл. по умолчанию).
    @Published public var doubleShiftFixEnabled: Bool {
        didSet { defaults.set(doubleShiftFixEnabled, forKey: Key.doubleShiftFixEnabled) }
    }

    /// Single-Shift меняет раскладку (опционально, выкл. по умолчанию — FR-4).
    @Published public var singleShiftSwitchEnabled: Bool {
        didSet { defaults.set(singleShiftSwitchEnabled, forKey: Key.singleShiftSwitchEnabled) }
    }

    /// Разрешить откат последнего авто-исправления через Double-Shift (FR-4).
    @Published public var undoLastEnabled: Bool {
        didSet { defaults.set(undoLastEnabled, forKey: Key.undoLastEnabled) }
    }

    /// Окно двойного нажатия Shift, сек (0.2…0.6).
    @Published public var shiftGestureWindow: Double {
        didSet { defaults.set(shiftGestureWindow, forKey: Key.shiftGestureWindow) }
    }

    // MARK: - Автозамена текста (FR-7)

    @Published public var textExpansionEnabled: Bool {
        didSet { defaults.set(textExpansionEnabled, forKey: Key.textExpansionEnabled) }
    }

    /// Правила автозамены: сокращение → развёрнутый текст.
    @Published public var expansionRules: [String: String] {
        didSet { defaults.set(expansionRules, forKey: Key.expansionRules) }
    }

    // MARK: - Языки детекта

    /// Активные раскладки детекта (по умолчанию обе). Хранятся как rawValue.
    @Published public var detectionLanguages: [String] {
        didSet { defaults.set(detectionLanguages, forKey: Key.detectionLanguages) }
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
            Key.neverCorrectWords: [String](),
            Key.alwaysCorrectWords: [String](),
            Key.doubleShiftFixEnabled: true,
            Key.singleShiftSwitchEnabled: false,
            Key.undoLastEnabled: true,
            Key.shiftGestureWindow: 0.4,
            Key.textExpansionEnabled: true,
            Key.expansionRules: [String: String](),
            Key.detectionLanguages: ["en", "ru"],
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
        alwaysCorrectWords = defaults.stringArray(forKey: Key.alwaysCorrectWords) ?? []
        doubleShiftFixEnabled = defaults.bool(forKey: Key.doubleShiftFixEnabled)
        singleShiftSwitchEnabled = defaults.bool(forKey: Key.singleShiftSwitchEnabled)
        undoLastEnabled = defaults.bool(forKey: Key.undoLastEnabled)
        shiftGestureWindow = defaults.double(forKey: Key.shiftGestureWindow)
        textExpansionEnabled = defaults.bool(forKey: Key.textExpansionEnabled)
        expansionRules = defaults.dictionary(forKey: Key.expansionRules) as? [String: String] ?? [:]
        detectionLanguages = defaults.stringArray(forKey: Key.detectionLanguages) ?? ["en", "ru"]
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
    }

    /// Активно ли авто-исправление прямо сейчас (вкл. и не на паузе).
    public var isActive: Bool {
        guard enabled else { return false }
        if let pausedUntil, pausedUntil > Date() { return false }
        return true
    }
}
