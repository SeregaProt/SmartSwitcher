import CoreGraphics
import Foundation

/// Центральная логика (поток данных из раздела 3.3 ТЗ):
/// событие клавиши → буфер слова → на границе слова → автозамена/детектор →
/// правила → при уверенном вердикте → смена раскладки + перенабор.
///
/// Все события обрабатываются на одной серийной очереди: поток event tap
/// возвращается мгновенно (низкая латентность горячего пути, NFR < 5 мс),
/// а состояние буфера и детектора жестов не требует блокировок.
public final class SwitcherEngine {
    private enum KeyCode {
        static let backspace: Int64 = 51
        static let forwardDelete: Int64 = 117
        static let returnKey: Int64 = 36
        static let keypadEnter: Int64 = 76
        static let tab: Int64 = 48
        static let escape: Int64 = 53
        static let arrows: Set<Int64> = [123, 124, 125, 126]
        static let navigation: Set<Int64> = [115, 116, 119, 121] // Home, PgUp, End, PgDn
    }

    /// Разделители, идентичные в обеих раскладках, — после них безопасно
    /// перенабирать слово вместе с разделителем.
    private static let correctableSeparators = Set<Character>(" !()%*+=")

    private let detector: LanguageDetector
    private let buffer: InputBuffer
    private let layouts: LayoutController
    private let replacer: TextReplacer
    private let exclusions: AppExclusionManager
    private let wordRules: WordRulesManager
    private let preferences: Preferences
    private let focus: FocusInspector
    private let diary: DiaryService?
    private let expander: TextExpander?
    private let gestures = ShiftGestureDetector()
    private let queue = DispatchQueue(label: "com.smartswitcher.engine", qos: .userInteractive)

    /// Уведомление UI об исправлении (звук, обновление иконки, нотификация).
    public var onCorrection: ((Layout) -> Void)?

    /// Последнее авто-исправление — для отката и самообучения (FR-6).
    private var lastAutoCorrection: (original: String, replacement: String, date: Date)?
    private let undoLearningWindow: TimeInterval = 30

    public init(
        detector: LanguageDetector,
        buffer: InputBuffer,
        layouts: LayoutController,
        replacer: TextReplacer,
        exclusions: AppExclusionManager,
        wordRules: WordRulesManager,
        preferences: Preferences,
        focus: FocusInspector,
        diary: DiaryService? = nil,
        expander: TextExpander? = nil
    ) {
        self.detector = detector
        self.buffer = buffer
        self.layouts = layouts
        self.replacer = replacer
        self.exclusions = exclusions
        self.wordRules = wordRules
        self.preferences = preferences
        self.focus = focus
        self.diary = diary
        self.expander = expander
    }

    // MARK: - Вход событий (поток event tap → серийная очередь)

    public func handle(_ event: EventTapManager.TapEvent) {
        queue.async { [weak self] in self?.process(event) }
    }

    private func process(_ event: EventTapManager.TapEvent) {
        switch event {
        case .mouseDown:
            buffer.reset()

        case let .flagsChanged(keyCode, flags, timestamp):
            gestures.setWindow(preferences.shiftGestureWindow)
            let gesture = gestures.handleFlagsChanged(keyCode: keyCode, flags: flags, time: timestamp)
            handle(gesture: gesture)
            scheduleSingleShiftCheck(after: timestamp)

        case let .keyDown(keyCode, flags, characters):
            handleKeyDown(keyCode: keyCode, flags: flags, characters: characters)
        }
    }

    // MARK: - Жесты Shift (FR-4)

    private func handle(gesture: ShiftGesture) {
        switch gesture {
        case .double where preferences.doubleShiftFixEnabled:
            manualFix()
        case .single where preferences.singleShiftSwitchEnabled:
            toggleLayout()
        default:
            break
        }
    }

    /// Single-Shift распознаётся только если за окно не пришло второе нажатие.
    private func scheduleSingleShiftCheck(after time: TimeInterval) {
        guard preferences.singleShiftSwitchEnabled else { return }
        let window = preferences.shiftGestureWindow
        queue.asyncAfter(deadline: .now() + window + 0.02) { [weak self] in
            guard let self else { return }
            if self.gestures.pendingSingle(now: time + window + 0.02) == .single {
                self.toggleLayout()
            }
        }
    }

    private func toggleLayout() {
        let target = (layouts.current() ?? .en).other
        layouts.select(target)
        Log.engine.info("Single-Shift: смена раскладки на \(target.rawValue)")
        onCorrection?(target)
    }

    // MARK: - Обработка клавиш

    private func handleKeyDown(keyCode: Int64, flags: CGEventFlags, characters: String) {
        gestures.noteKeyDown()

        // Cmd/Ctrl/Option-комбинации — контекст набора потерян.
        if !flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty {
            buffer.reset()
            return
        }

        switch keyCode {
        case KeyCode.backspace:
            buffer.backspace()
            return
        case KeyCode.returnKey, KeyCode.keypadEnter, KeyCode.tab:
            // Фиксируем слово без авто-исправления раскладки: перенабор «сквозь»
            // Enter опасен (ADR-0005). Но автозамену (FR-7) применяем — она
            // безопасна и ожидаема пользователем.
            if let token = buffer.commit(separator: "") {
                tryExpand(token: token, separator: "")
            }
            return
        case KeyCode.escape, KeyCode.forwardDelete:
            buffer.reset()
            return
        case _ where KeyCode.arrows.contains(keyCode) || KeyCode.navigation.contains(keyCode):
            buffer.reset()
            return
        default:
            break
        }

        guard characters.count == 1, let ch = characters.first else {
            if !characters.isEmpty { buffer.taint() }
            return
        }

        if Self.correctableSeparators.contains(ch) {
            commitAndCorrect(separator: String(ch))
        } else if InputBuffer.isBufferable(ch) {
            buffer.append(ch)
        } else {
            if ch.isWhitespace {
                if let token = buffer.commit(separator: String(ch)) {
                    tryExpand(token: token, separator: String(ch))
                }
            } else {
                buffer.taint()
            }
        }
    }

    // MARK: - Автозамена (FR-7)

    /// Пытается применить правило автозамены к закоммиченному токену.
    /// Возвращает true, если замена выполнена (тогда детектор раскладки пропускаем).
    @discardableResult
    private func tryExpand(token: String, separator: String) -> Bool {
        guard preferences.isActive else { return false }
        guard !exclusions.isFrontmostExcluded() else { return false }
        guard !focus.isSecureFieldFocused() else { return false }
        guard let expansion = expander?.expansion(for: token) else { return false }

        replacer.replace(deleteCount: token.count + separator.count, with: expansion + separator)
        buffer.setLastCommitted(word: expansion, separator: separator)
        Log.engine.info("Автозамена: \(token.count) симв. → \(expansion.count) симв.")
        return true
    }

    // MARK: - Авто-исправление на границе слова

    private func commitAndCorrect(separator: String) {
        guard let token = buffer.commit(separator: separator) else { return }
        guard preferences.isActive else { return }
        guard !exclusions.isFrontmostExcluded() else { return }
        guard !focus.isSecureFieldFocused() else { return }

        // Автозамена имеет приоритет над детектором раскладки (FR-7).
        if tryExpand(token: token, separator: separator) { return }

        guard token.count >= 2 else { return }

        let core = TokenUtils.core(of: token).lowercased()
        guard !wordRules.isNeverCorrect(core) else { return }

        let verdict: Verdict
        if wordRules.isAlwaysCorrect(core) {
            verdict = forcedVerdict(for: token)
        } else {
            verdict = detector.analyze(token)
        }
        guard case let .correct(layout, replacement) = verdict else { return }

        replacer.replace(
            deleteCount: token.count + separator.count,
            with: replacement + separator
        )
        layouts.select(layout)
        lastAutoCorrection = (token, replacement, Date())
        buffer.setLastCommitted(word: replacement, separator: separator)
        diary?.record(
            original: token,
            corrected: replacement,
            app: exclusions.frontmostBundleID(),
            manual: false
        )
        Log.engine.info("Авто-исправление: \(token.count) симв. → раскладка \(layout.rawValue)")
        onCorrection?(layout)
    }

    /// Принудительная конвертация для слов из списка «всегда исправлять».
    private func forcedVerdict(for token: String) -> Verdict {
        switch TokenUtils.script(of: token) {
        case .latin:
            if let converted = LayoutMapping.toRussian(token) {
                return .correct(layout: .ru, replacement: converted)
            }
        case .cyrillic:
            if let converted = LayoutMapping.toEnglish(token) {
                return .correct(layout: .en, replacement: converted)
            }
        case .mixed, .none:
            break
        }
        return .keep
    }

    // MARK: - Ручное исправление (Double-Shift, FR-4)

    private func manualFix() {
        guard preferences.enabled else { return }

        let isCurrentWord = !buffer.current.isEmpty && !buffer.isTainted
        let token: String
        let separator: String
        if isCurrentWord {
            token = buffer.current
            separator = ""
        } else if let last = buffer.lastCommitted {
            token = last.word
            separator = last.separator
        } else {
            return
        }

        guard case let .correct(target, replacement) = forcedVerdict(for: token) else { return }

        replacer.replace(
            deleteCount: token.count + separator.count,
            with: replacement + separator
        )
        layouts.select(target)

        if isCurrentWord {
            buffer.replaceCurrent(with: replacement)
        } else {
            buffer.setLastCommitted(word: replacement, separator: separator)
        }

        // Откат свежего авто-исправления → самообучение (FR-6), если разрешено.
        if preferences.undoLastEnabled,
           let auto = lastAutoCorrection,
           token == auto.replacement,
           Date().timeIntervalSince(auto.date) < undoLearningWindow {
            wordRules.addNeverCorrect(auto.original)
            Log.engine.info("Самообучение: слово добавлено в исключения (длина \(auto.original.count))")
            lastAutoCorrection = nil
        }

        diary?.record(
            original: token,
            corrected: replacement,
            app: exclusions.frontmostBundleID(),
            manual: true
        )
        Log.engine.info("Ручное исправление Double-Shift → раскладка \(target.rawValue)")
        onCorrection?(target)
    }
}
