import AppKit
import Carbon
import SmartSwitcherKit

/// Интеграционный тест (ТЗ 7.1, 7.2): связка детект → правила → перенабор
/// на РЕАЛЬНОМ `SwitcherEngine` из production-кода.
///
/// Синтетические события клавиш подаются напрямую в `engine.handle(...)`,
/// минуя `CGEventTap` (поэтому тест не требует прав Accessibility). Дальше
/// engine сам вызывает настоящий `TextReplacer`, который печатает результат
/// в собственное окно теста — мы читаем его и сверяем с ожиданием.
final class IntegrationApp: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var textView: NSTextView!
    private var engine: SwitcherEngine!
    private let layouts = LayoutController()
    private var failures = 0
    private var passed = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        let defaults = UserDefaults(suiteName: "com.smartswitcher.integration")!
        defaults.removePersistentDomain(forName: "com.smartswitcher.integration")
        let preferences = Preferences(defaults: defaults)

        let dictionaries = DictionaryService()
        let ngrams = NGramModel()
        dictionaries.warmUp()
        ngrams.warmUp()

        engine = SwitcherEngine(
            detector: StatisticalDetector(dictionaries: dictionaries, ngrams: ngrams),
            buffer: InputBuffer(),
            layouts: layouts,
            replacer: TextReplacer(),
            exclusions: AppExclusionManager(preferences: preferences),
            wordRules: WordRulesManager(preferences: preferences),
            preferences: preferences,
            focus: FocusInspector()
        )

        textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 160))
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 160),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "SmartSwitcher Integration"
        window.contentView = textView
        window.center()
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(textView)

        DispatchQueue.global().async { self.runScenarios() }
    }

    /// Имитация реального набора: каждый символ сначала «печатается» в поле
    /// (как настоящее нажатие, которое listen-only tap только наблюдает),
    /// затем отдаётся движку. На разделителе движок может вызвать TextReplacer,
    /// который удалит мусор и впечатает исправление поверх уже набранного.
    private func feed(_ text: String) {
        for ch in text {
            DispatchQueue.main.sync { self.textView.insertText(String(ch), replacementRange: NSRange(location: NSNotFound, length: 0)) }
            let keyCode: Int64 = ch == " " ? 49 : 0
            let event = EventTapManager.TapEvent.keyDown(
                keyCode: keyCode,
                flags: [],
                characters: String(ch)
            )
            DispatchQueue.main.sync { self.engine.handle(event) }
            usleep(20000)
        }
    }

    private func currentLayoutID() -> String {
        let src = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let ptr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else { return "?" }
        return Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue() as? String ?? "?"
    }

    private func scenario(_ name: String, type input: String, expect expected: String) {
        DispatchQueue.main.sync { self.textView.string = "" }
        feed(input)
        usleep(500000) // даём TextReplacer допечатать
        let result = DispatchQueue.main.sync { self.textView.string }
        if result == expected {
            passed += 1
            print("  ✓ \(name): '\(input.trimmingCharacters(in: .whitespaces))' → '\(result)'")
        } else {
            failures += 1
            print("  ✗ \(name): ожидалось '\(expected)', получено '\(result)'")
        }
    }

    private func runScenarios() {
        usleep(900000)
        print("▶︎ Интеграция: реальный SwitcherEngine + TextReplacer")

        // Раскладку перед каждым «латинским» сценарием ставим в US, чтобы
        // символы отражали реальную ситуацию набора.
        layoutSync(.en)
        scenario("русское слово в EN", type: "ghbdtn ", expect: "привет ")
        // После исправления системная раскладка обязана стать русской (запрос
        // пользователя: переключать язык на уровне системы, не пословно).
        // current() потокобезопасен (кеш), TIS напрямую с этого потока звать нельзя.
        var switched = false
        for _ in 0..<20 {
            usleep(100000)
            if layouts.current() == .ru { switched = true; break }
        }
        if switched {
            passed += 1
            print("  ✓ системная раскладка переключилась на RU")
        } else {
            failures += 1
            print("  ✗ системная раскладка НЕ переключилась (current=\(layouts.current().map { $0.rawValue } ?? "nil"))")
        }

        layoutSync(.en)
        scenario("осмысленное EN-слово не трогается", type: "hello ", expect: "hello ")

        layoutSync(.en)
        scenario("стоп-лист: число не трогается", type: "test123 ", expect: "test123 ")

        layoutSync(.ru)
        scenario("английское слово в RU", type: "руддщ ", expect: "hello ")

        DispatchQueue.main.async {
            print(self.failures == 0
                ? "\n✓ Интеграция пройдена: \(self.passed)"
                : "\n✗ Интеграция: провалено \(self.failures), пройдено \(self.passed)")
            NSApp.terminate(nil)
            exit(self.failures == 0 ? 0 : 1)
        }
    }

    private func layoutSync(_ layout: Layout) {
        DispatchQueue.main.sync { self.layouts.select(layout) }
        usleep(200000)
    }
}

setbuf(stdout, nil)
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = IntegrationApp()
app.delegate = delegate
app.run()
