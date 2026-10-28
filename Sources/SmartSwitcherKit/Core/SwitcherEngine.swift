import CoreGraphics
import Foundation

/// Центральная логика (поток данных из раздела 3.3 ТЗ):
/// событие клавиши → буфер слова → на границе слова → автозамена/детектор →
/// правила → при уверенном вердикте → смена раскладки + перенабор.
///
/// Все события обрабатываются на одной серийной очереди: поток event tap
/// возвращается мгновенно (низкая латентность горячего пути, NFR < 5 мс),
/// а состояние буфера и детектора жестов не требует блокировок.
/// Настройки читаются из потокобезопасного снимка `Preferences.engine`.
///
/// `@unchecked Sendable`: изменяемое состояние трогается только на `queue`,
/// `onCorrection` задаётся один раз при сборке приложения.
public final class SwitcherEngine: @unchecked Sendable {
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

    /// Сколько секунд язык предыдущих слов считается контекстом фразы.
    private static let phraseContextLifetime: TimeInterval = 30
    /// Окно отката авто-исправления Backspace'ом.
    private static let backspaceUndoWindow: TimeInterval = 5
    private static let undoLearningWindow: TimeInterval = 30

    private let detector: LanguageDetector
    private let buffer: InputBuffer
    private let layouts: LayoutController
    private let replacer: TextReplacer
    private let appRules: AppRulesManager
    private let wordRules: WordRulesManager
    private let preferences: Preferences
    private let focus: FocusInspector
    private let converter: LayoutConverting
    private let personal: PersonalDictionary?
    private let diary: DiaryService?
    private let expander: TextExpander?
    private let stats: StatisticsService?
    private let gestures = ShiftGestureDetector()
    private let queue = DispatchQueue(label: "com.smartswitcher.engine", qos: .userInteractive)

    /// Уведомление UI об исправлении (звук, иконка, HUD, нотификация).
    public var onCorrection: ((Layout) -> Void)?

    /// Последнее авто-исправление — для отката и самообучения (FR-6).
    private var lastAutoCorrection: (original: String, replacement: String, date: Date)?
    /// Откат Backspace'ом возможен, пока после исправления не было других клавиш.
    private var pendingUndo: (original: String, replacement: String, separator: String,
                              source: Layout, date: Date)?
    /// Слово, оставленное без исправления; подтверждается следующим словом.
    private var pendingLearn: (word: String, layout: Layout)?
    private var phrase: (layout: Layout, date: Date)?
    private var capsLockOn = false

    public init(
        detector: LanguageDetector,
        buffer: InputBuffer,
        layouts: LayoutController,
        replacer: TextReplacer,
        appRules: AppRulesManager,
        wordRules: WordRulesManager,
        preferences: Preferences,
        focus: FocusInspector,
        converter: LayoutConverting = StaticLayoutConverter(),
        personal: PersonalDictionary? = nil,
        diary: DiaryService? = nil,
        expander: TextExpander? = nil,
        stats: StatisticsService? = nil
    ) {
        self.detector = detector
        self.buffer = buffer
        self.layouts = layouts
        self.replacer = replacer
        self.appRules = appRules
        self.wordRules = wordRules
        self.preferences = preferences
        self.focus = focus
        self.converter = converter
        self.personal = personal
        self.diary = diary
        self.expander = expander
        self.stats = stats
    }

    // MARK: - Вход событий (поток event tap → серийная очередь)

    public func handle(_ event: EventTapManager.TapEvent) {
        queue.async { [weak self] in self?.process(event) }
    }

    /// Вызывается активным tap'ом на Enter (ADR-0008). Решение принимается
    /// синхронно: если слово перед курсором нужно исправить, ввод сразу
    /// придерживается, исходный Enter поглощается, а исправление и повтор
    /// Enter выполняются на очереди движка. true — Enter поглотить.
    public func interceptEnter(flags: CGEventFlags) -> Bool {
        queue.sync {
            guard let plan = planBeforeEnter() else { return false }
            replacer.gate?.hold()
            queue.async { [weak self] in
                self?.executeBeforeEnter(plan, flags: flags)
                self?.replacer.gate?.release()
            }
            return true
        }
    }

    private func process(_ event: EventTapManager.TapEvent) {
        switch event {
        case .mouseDown:
            loseCursorContext()

        case .contextLost:
            loseCursorContext()
            phrase = nil

        case let .flagsChanged(keyCode, flags, timestamp):
            gestures.setWindow(preferences.engine.shiftGestureWindow)
            let gesture = gestures.handleFlagsChanged(keyCode: keyCode, flags: flags, time: timestamp)
            handle(gesture: gesture)
            scheduleSingleShiftCheck(after: timestamp)

        case let .keyDown(keyCode, flags, characters):
            handleKeyDown(keyCode: keyCode, flags: flags, characters: characters)
        }
    }

    /// Курсор мог переместиться: буфер, последнее слово и откаты недостоверны.
    private func loseCursorContext() {
        buffer.reset()
        pendingUndo = nil
        pendingLearn = nil
    }

    // MARK: - Жесты Shift (FR-4)

    private func handle(gesture: ShiftGesture) {
        let settings = preferences.engine
        switch gesture {
        case .double where settings.doubleShiftFixEnabled:
            manualFix()
        case .single where settings.singleShiftSwitchEnabled:
            toggleLayout()
        default:
            break
        }
    }

    /// Single-Shift распознаётся только если за окно не пришло второе нажатие.
    private func scheduleSingleShiftCheck(after time: TimeInterval) {
        let settings = preferences.engine
        guard settings.singleShiftSwitchEnabled else { return }
        let window = settings.shiftGestureWindow
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
        capsLockOn = flags.contains(.maskAlphaShift)

        // Cmd/Ctrl/Option-комбинации — контекст набора потерян.
        if !flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty {
            loseCursorContext()
            return
        }

        if keyCode == KeyCode.backspace {
            if undoByBackspace() { return }
            pendingUndo = nil
            // Возврат в предыдущее слово — оно ещё не «оставлено».
            if buffer.current.isEmpty { pendingLearn = nil }
            buffer.backspace()
            return
        }
        pendingUndo = nil

        switch keyCode {
        case KeyCode.returnKey, KeyCode.keypadEnter, KeyCode.tab:
            // Слово фиксируется без исправления и без запоминания: перенабор
            // «сквозь» Enter/Tab опасен (ADR-0005). Исправление перед Enter —
            // отдельная опция с активным tap (ADR-0008).
            confirmPendingLearn()
            if let token = buffer.commit(separator: "", remember: false) {
                notePhrase(of: token)
            }
            return
        case KeyCode.escape, KeyCode.forwardDelete:
            loseCursorContext()
            return
        case _ where KeyCode.arrows.contains(keyCode) || KeyCode.navigation.contains(keyCode):
            loseCursorContext()
            return
        default:
            break
        }

        guard characters.count == 1, let ch = characters.first else {
            // Составные символы (dead keys) — слово анализу не подлежит.
            for ch in characters { buffer.append(ch) }
            if !characters.isEmpty { buffer.taint() }
            return
        }

        if Self.correctableSeparators.contains(ch) {
            commitAndCorrect(separator: String(ch))
        } else if ch.isWhitespace {
            // Прочие пробельные (неразрывный пробел и т.п.) — только автозамена.
            confirmPendingLearn()
            if let token = buffer.commit(separator: String(ch)) {
                if !tryExpand(token: token, separator: String(ch), settings: preferences.engine) {
                    notePhrase(of: token)
                }
            }
        } else {
            buffer.append(ch)
        }
    }

    // MARK: - Автозамена (FR-7)

    /// Пытается применить правило автозамены к закоммиченному токену.
    /// Возвращает true, если замена выполнена (тогда детектор раскладки пропускаем).
    private func tryExpand(token: String, separator: String, settings: EngineSettings) -> Bool {
        guard settings.isActive(),
              appRules.frontmostMode() == .auto,
              let expansion = expander?.expansion(for: token),
              !focus.isSecureInputActive() else { return false }

        replacer.replace(deleteCount: token.count + separator.count, with: expansion + separator)
        buffer.setLastCommitted(word: expansion, separator: separator)
        stats?.record(.expansion, savedKeystrokes: max(0, expansion.count - token.count))
        Log.engine.info("Автозамена: \(token.count) симв. → \(expansion.count) симв.")
        return true
    }

    // MARK: - Авто-исправление на границе слова

    private func commitAndCorrect(separator: String) {
        confirmPendingLearn()
        guard let token = buffer.commit(separator: separator) else { return }
        let settings = preferences.engine
        guard settings.isActive(),
              appRules.frontmostMode() == .auto,
              !focus.isSecureInputActive() else {
            notePhrase(of: token)
            return
        }

        // Автозамена имеет приоритет над детектором раскладки (FR-7).
        if tryExpand(token: token, separator: separator, settings: settings) { return }

        guard let (layout, replacement) = verdict(for: token, settings: settings) else {
            notePhrase(of: token)
            scheduleLearning(of: token, settings: settings)
            return
        }
        applyCorrection(token: token, replacement: replacement, layout: layout, separator: separator)
    }

    /// Решение по слову с учётом правил пользователя и контекста фразы.
    private func verdict(for token: String, settings: EngineSettings) -> (Layout, String)? {
        let core = TokenUtils.core(of: token).lowercased()
        guard !core.isEmpty, !settings.neverCorrectWords.contains(core) else { return nil }

        let verdict: Verdict
        if settings.alwaysCorrectWords.contains(core) {
            verdict = forcedVerdict(for: token)
        } else {
            verdict = detector.analyze(token, context: DetectionContext(
                previousLanguage: phraseLanguage(),
                capsLock: capsLockOn
            ))
        }
        guard case let .correct(layout, replacement) = verdict,
              settings.detectionLanguages.contains(layout) else { return nil }
        return (layout, replacement)
    }

    private func applyCorrection(token: String, replacement: String, layout: Layout, separator: String) {
        // Сначала раскладка: следующие нажатия пользователя уже пойдут в нужной.
        layouts.select(layout)
        replacer.replace(
            deleteCount: token.count + separator.count,
            with: replacement + separator
        )
        lastAutoCorrection = (token, replacement, Date())
        pendingUndo = (token, replacement, separator, layout.other, Date())
        buffer.setLastCommitted(word: replacement, separator: separator)
        phrase = (layout, Date())
        diary?.record(
            original: token,
            corrected: replacement,
            app: appRules.frontmostBundleID(),
            manual: false
        )
        stats?.record(.auto, savedKeystrokes: 2 * token.count + 2)
        Log.engine.info("Авто-исправление: \(token.count) симв. → раскладка \(layout.rawValue)")
        onCorrection?(layout)
    }

    /// Принудительная конвертация (слова «всегда исправлять», Double-Shift).
    private func forcedVerdict(for token: String) -> Verdict {
        let source: Layout
        switch TokenUtils.script(of: token) {
        case .latin: source = .en
        case .cyrillic: source = .ru
        case .mixed, .none: return .keep
        }
        guard let converted = converter.convert(token, from: source, to: source.other) else {
            return .keep
        }
        return .correct(layout: source.other, replacement: converted)
    }

    // MARK: - Исправление перед Enter (ADR-0008)

    private enum EnterPlan {
        case expand(token: String, expansion: String)
        case correct(token: String, replacement: String, layout: Layout)
    }

    private func planBeforeEnter() -> EnterPlan? {
        let settings = preferences.engine
        guard settings.reliableMode,
              settings.isActive(),
              appRules.frontmostMode() == .auto,
              !buffer.current.isEmpty, !buffer.isTainted,
              !focus.isSecureInputActive() else { return nil }
        let token = buffer.current
        if let expansion = expander?.expansion(for: token) {
            return .expand(token: token, expansion: expansion)
        }
        if let (layout, replacement) = verdict(for: token, settings: settings) {
            return .correct(token: token, replacement: replacement, layout: layout)
        }
        return nil
    }

    private func executeBeforeEnter(_ plan: EnterPlan, flags: CGEventFlags) {
        switch plan {
        case let .expand(token, expansion):
            replacer.replace(deleteCount: token.count, with: expansion)
            stats?.record(.expansion, savedKeystrokes: max(0, expansion.count - token.count))
        case let .correct(token, replacement, layout):
            applyCorrection(token: token, replacement: replacement, layout: layout, separator: "")
        }
        // Слово уходит вместе с Enter — откатывать его уже нельзя.
        confirmPendingLearn()
        buffer.commit(separator: "", remember: false)
        pendingUndo = nil
        replacer.postReturn(flags: flags)
    }

    // MARK: - Откат Backspace'ом (opt-in)

    /// Backspace сразу после авто-исправления: пользователь стёр разделитель —
    /// возвращаем исходное слово и раскладку.
    private func undoByBackspace() -> Bool {
        guard preferences.engine.backspaceUndoEnabled,
              let undo = pendingUndo,
              !undo.separator.isEmpty,
              Date().timeIntervalSince(undo.date) < Self.backspaceUndoWindow else { return false }
        pendingUndo = nil
        layouts.select(undo.source)
        replacer.replace(deleteCount: undo.replacement.count, with: undo.original)
        buffer.reset()
        buffer.replaceCurrent(with: undo.original)
        learnFromUndo(of: undo.replacement)
        phrase = (undo.source, Date())
        stats?.record(.undo)
        Log.engine.info("Откат Backspace → раскладка \(undo.source.rawValue)")
        onCorrection?(undo.source)
        return true
    }

    // MARK: - Ручное исправление (Double-Shift, FR-4)

    private func manualFix() {
        let settings = preferences.engine
        guard settings.isActive(),
              appRules.frontmostMode() != .off,
              !focus.isSecureInputActive() else { return }

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

        layouts.select(target)
        replacer.replace(
            deleteCount: token.count + separator.count,
            with: replacement + separator
        )

        if isCurrentWord {
            buffer.replaceCurrent(with: replacement)
        } else {
            buffer.setLastCommitted(word: replacement, separator: separator)
        }

        // Пользователь не согласен с тем, как слово было набрано, — не учим его.
        pendingLearn = nil
        pendingUndo = nil
        personal?.forget(TokenUtils.core(of: token).lowercased(), in: target.other)
        phrase = (target, Date())

        let isUndo = learnFromUndo(of: token)
        diary?.record(
            original: token,
            corrected: replacement,
            app: appRules.frontmostBundleID(),
            manual: true
        )
        stats?.record(isUndo ? .undo : .manual, savedKeystrokes: isUndo ? 0 : 2 * token.count)
        Log.engine.info("Ручное исправление Double-Shift → раскладка \(target.rawValue)")
        onCorrection?(target)
    }

    /// Откат свежего авто-исправления → самообучение (FR-6), если разрешено.
    @discardableResult
    private func learnFromUndo(of replacement: String) -> Bool {
        guard let auto = lastAutoCorrection,
              replacement == auto.replacement,
              Date().timeIntervalSince(auto.date) < Self.undoLearningWindow else { return false }
        lastAutoCorrection = nil
        if preferences.engine.undoLastEnabled {
            wordRules.addNeverCorrect(auto.original)
            Log.engine.info("Самообучение: слово добавлено в исключения (длина \(auto.original.count))")
        }
        return true
    }

    // MARK: - Контекст фразы и личный словарь

    private func phraseLanguage() -> Layout? {
        guard let phrase, Date().timeIntervalSince(phrase.date) < Self.phraseContextLifetime else {
            return nil
        }
        return phrase.layout
    }

    private func notePhrase(of word: String) {
        switch TokenUtils.script(of: word) {
        case .latin: phrase = (.en, Date())
        case .cyrillic: phrase = (.ru, Date())
        case .mixed, .none: break
        }
    }

    private func scheduleLearning(of token: String, settings: EngineSettings) {
        guard settings.learnFromTyping, personal != nil,
              !StopRules.shouldIgnore(token) else { return }
        let core = TokenUtils.core(of: token).lowercased()
        guard core.count >= 2 else { return }
        switch TokenUtils.script(of: core) {
        case .latin: pendingLearn = (core, .en)
        case .cyrillic: pendingLearn = (core, .ru)
        case .mixed, .none: pendingLearn = nil
        }
    }

    private func confirmPendingLearn() {
        if let pending = pendingLearn {
            personal?.noteKept(pending.word, in: pending.layout)
        }
        pendingLearn = nil
    }
}
