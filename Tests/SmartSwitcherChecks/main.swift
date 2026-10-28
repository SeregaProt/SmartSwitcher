import CoreGraphics
import Foundation
import SmartSwitcherKit

// MARK: - LayoutMapping

suite("LayoutMapping: EN → RU") {
    expect(LayoutMapping.toRussian("ghbdtn") == "привет", "ghbdtn → привет")
    expect(LayoutMapping.toRussian("ckjdj") == "слово", "ckjdj → слово")
    expect(LayoutMapping.toRussian("rfr") == "как", "rfr → как")
    expect(LayoutMapping.toRussian("ltkf") == "дела", "ltkf → дела")
    expect(LayoutMapping.toRussian("xnj") == "что", "xnj → что")
}

suite("LayoutMapping: RU → EN") {
    expect(LayoutMapping.toEnglish("руддщ") == "hello", "руддщ → hello")
    expect(LayoutMapping.toEnglish("еру") == "the", "еру → the")
    expect(LayoutMapping.toEnglish("ьфс") == "mac", "ьфс → mac")
}

suite("LayoutMapping: регистр") {
    expect(LayoutMapping.toRussian("Ghbdtn") == "Привет", "Ghbdtn → Привет")
    expect(LayoutMapping.toRussian("GHBDTN") == "ПРИВЕТ", "GHBDTN → ПРИВЕТ")
    expect(LayoutMapping.toEnglish("Руддщ") == "Hello", "Руддщ → Hello")
}

suite("LayoutMapping: пунктуация-буквы") {
    expect(LayoutMapping.toRussian("cgfcb,j") == "спасибо", "cgfcb,j → спасибо")
    expect(LayoutMapping.toRussian("ghbdtn?") == "привет,", "ghbdtn? → привет,")
    expect(LayoutMapping.toRussian(";tcnm") == "жесть", ";tcnm → жесть")
    expect(LayoutMapping.toRussian("[jhjij") == "хорошо", "[jhjij → хорошо")
    expect(LayoutMapping.toEnglish("руддщб") == "hello,", "руддщб → hello,")
    expect(LayoutMapping.toEnglish("руддщю") == "hello.", "руддщю → hello.")
}

suite("LayoutMapping: немаппируемое и round-trip") {
    expect(LayoutMapping.toRussian("abc123") == nil, "цифры → nil")
    expect(LayoutMapping.toRussian("日本語") == nil, "CJK → nil")
    expect(
        LayoutMapping.toRussian("ghbdtn").flatMap(LayoutMapping.toEnglish) == "ghbdtn",
        "round-trip ghbdtn"
    )
}

// MARK: - Детектор: базовые случаи

let baseDetector: StatisticalDetector = {
    let dictionaries = DictionaryService()
    let ngrams = NGramModel()
    dictionaries.warmUp()
    ngrams.warmUp()
    return StatisticalDetector(dictionaries: dictionaries, ngrams: ngrams)
}()

suite("Детектор: русский мусор в EN-раскладке исправляется") {
    let corrections: [(String, String)] = [
        ("ghbdtn", "привет"),
        ("ckjdj", "слово"),
        ("rfr", "как"),
        ("ltkf", "дела"),
        ("xnj", "что"),
        ("cgfcb,j", "спасибо"),
        ("vjcrdf", "москва"),
        ("[jhjij", "хорошо"),
        ("ctujlyz", "сегодня"),
        ("hf,jnf", "работа"),
        ("Ghbdtn", "Привет"),
        ("ghbdtn?", "привет,"),
    ]
    for (input, expected) in corrections {
        let verdict = baseDetector.analyze(input)
        expect(verdict == .correct(layout: .ru, replacement: expected), "\(input) → \(expected), получено: \(verdict)")
    }
}

suite("Детектор: английский мусор в RU-раскладке исправляется") {
    let corrections: [(String, String)] = [
        ("руддщ", "hello"),
        ("еру", "the"),
        ("цщкв", "word"),
        ("руддщб", "hello,"),
    ]
    for (input, expected) in corrections {
        let verdict = baseDetector.analyze(input)
        expect(verdict == .correct(layout: .en, replacement: expected), "\(input) → \(expected), получено: \(verdict)")
    }
}

suite("Детектор: нормальные слова не трогаются (precision)") {
    let words = [
        "hello", "the", "world", "swift", "don't", "qwerty",
        "really", "code", "github",
        "привет", "спасибо", "мама", "слово", "работа", "сегодня",
        "Привет", "файл", "огурец", "программа",
    ]
    for word in words {
        let verdict = baseDetector.analyze(word)
        expect(verdict == .keep, "не трогать: \(word), получено: \(verdict)")
    }
}

suite("Детектор: стоп-листы") {
    let tokens = [
        "test123", "v2", "127001",
        "user@mail.com", "example.com", "main.swift",
        "/usr/local", "~/Documents", "--force", "#hashtag",
        "snake_case", "camelCase", "McDonald", "HTML", "API", "GHBDTN",
    ]
    for token in tokens {
        expect(baseDetector.analyze(token) == .keep, "стоп-лист: \(token)")
    }
}

suite("Детектор: граничные случаи") {
    expect(baseDetector.analyze("a") == .keep, "одиночная буква EN без контекста")
    expect(baseDetector.analyze("я") == .keep, "одиночная буква RU без контекста")
    expect(baseDetector.analyze("d") == .keep, "«d» без контекста не трогаем")
    expect(baseDetector.analyze(String(repeating: "f", count: 40)) == .keep, "сверхдлинный токен")
    expect(baseDetector.analyze("abcабв") == .keep, "смешанная письменность")
}

suite("Детектор: контекст фразы") {
    let ru = DetectionContext(previousLanguage: .ru)
    let en = DetectionContext(previousLanguage: .en)
    expect(baseDetector.analyze("d", context: ru) == .correct(layout: .ru, replacement: "в"), "d после русских слов → в")
    expect(baseDetector.analyze("b", context: ru) == .correct(layout: .ru, replacement: "и"), "b после русских слов → и")
    expect(baseDetector.analyze("z", context: ru) == .correct(layout: .ru, replacement: "я"), "z после русских слов → я")
    expect(baseDetector.analyze("a", context: ru) == .keep, "a — английское слово, не трогаем")
    expect(baseDetector.analyze("ш", context: en) == .correct(layout: .en, replacement: "i"), "ш после английских слов → i")
    expect(baseDetector.analyze("в", context: en) == .keep, "в — русское слово, не трогаем")
    expect(baseDetector.analyze("d", context: en) == .keep, "d после английских — не трогаем")
}

suite("Детектор: Caps Lock") {
    let caps = DetectionContext(capsLock: true)
    expect(baseDetector.analyze("GHBDTN", context: caps) == .correct(layout: .ru, replacement: "ПРИВЕТ"), "GHBDTN при Caps Lock → ПРИВЕТ")
    expect(baseDetector.analyze("GHBDTN") == .keep, "без Caps Lock это аббревиатура")
    expect(baseDetector.analyze("HELLO", context: caps) == .keep, "HELLO при Caps Lock — английское слово")
}

suite("Личный словарь") {
    let defaults = UserDefaults(suiteName: "com.smartswitcher.personal-checks")!
    defaults.removePersistentDomain(forName: "com.smartswitcher.personal-checks")
    let personal = PersonalDictionary(storeURL: nil, defaults: defaults)
    expect(!personal.contains("kubectl", in: .en), "по умолчанию слово неизвестно")
    personal.noteKept("kubectl", in: .en)
    personal.noteKept("kubectl", in: .en)
    expect(!personal.contains("kubectl", in: .en), "двух подтверждений мало")
    personal.noteKept("kubectl", in: .en)
    expect(personal.contains("kubectl", in: .en), "три подтверждения — слово выучено")
    expect(!personal.contains("kubectl", in: .ru), "слово привязано к раскладке")
    expect(personal.learnedCount == 1, "счётчик выученных слов")
    personal.forget("kubectl", in: .en)
    expect(!personal.contains("kubectl", in: .en), "ручная правка сжигает подтверждения")

    let dictionaries = DictionaryService()
    let ngrams = NGramModel()
    let detector = StatisticalDetector(dictionaries: dictionaries, ngrams: ngrams, personal: personal)
    expect(detector.analyze("ghbdtn") != .keep, "до обучения ghbdtn исправляется")
    for _ in 0..<3 { personal.noteKept("ghbdtn", in: .en) }
    expect(detector.analyze("ghbdtn") == .keep, "выученное слово больше не исправляется")
    personal.clear()
    expect(personal.learnedCount == 0, "очистка личного словаря")
    defaults.removePersistentDomain(forName: "com.smartswitcher.personal-checks")
}

// MARK: - InputBuffer

suite("InputBuffer: накопление и коммит") {
    let buffer = InputBuffer()
    for ch in "ghbdtn" { buffer.append(ch) }
    expect(buffer.current == "ghbdtn", "буфер накопил слово")
    let token = buffer.commit(separator: " ")
    expect(token == "ghbdtn", "коммит вернул слово")
    expect(buffer.current.isEmpty, "буфер очищен после коммита")
    expect(buffer.lastCommitted?.word == "ghbdtn", "lastCommitted слово")
    expect(buffer.lastCommitted?.separator == " ", "lastCommitted разделитель")
}

suite("InputBuffer: backspace и таинт") {
    let buffer = InputBuffer()
    for ch in "abc" { buffer.append(ch) }
    buffer.backspace()
    expect(buffer.current == "ab", "backspace удалил символ")

    let tainted = InputBuffer()
    for ch in "abc" { tainted.append(ch) }
    tainted.append("1")
    expect(tainted.isTainted, "цифра загрязняет буфер")
    expect(tainted.commit(separator: " ") == nil, "загрязнённый буфер не коммитится")
    expect(!tainted.isTainted, "после коммита таинт снят")
    expect(tainted.lastCommitted == nil, "загрязнённое слово не запоминается")

    // Регрессия: раньше цифра не попадала в буфер, и Backspace стирал букву.
    let synced = InputBuffer()
    synced.append("a")
    synced.append("1")
    synced.backspace()
    expect(synced.current == "a" && !synced.isTainted, "Backspace стирает именно цифру — буфер синхронен с экраном")
}

suite("InputBuffer: переполнение и сброс") {
    let buffer = InputBuffer()
    for _ in 0..<(InputBuffer.maxLength + 5) { buffer.append("a") }
    expect(buffer.isTainted, "переполнение → таинт")

    // Регрессия P0: после клика/стрелок Double-Shift удалял символы в новом месте.
    let kept = InputBuffer()
    for ch in "word" { kept.append(ch) }
    kept.commit(separator: " ")
    kept.reset()
    expect(kept.lastCommitted == nil, "reset забывает последнее слово")
}

suite("InputBuffer: Enter/Tab и правка вслепую") {
    let enter = InputBuffer()
    for ch in "ghbdtn" { enter.append(ch) }
    expect(enter.commit(separator: "", remember: false) == "ghbdtn", "Enter возвращает слово")
    expect(enter.lastCommitted == nil, "после Enter слово не запоминается (P0)")

    let resume = InputBuffer()
    for ch in "ghbdtn" { resume.append(ch) }
    resume.commit(separator: " ")
    resume.backspace()
    expect(resume.current == "ghbdtn" && resume.lastCommitted == nil, "стёрт пробел — снова редактируем прошлое слово")

    let blind = InputBuffer()
    blind.backspace()
    for ch in "dtn" { blind.append(ch) }
    expect(blind.isTainted, "после стирания неизвестного текста набор — обрывок")
    expect(blind.commit(separator: " ") == nil, "обрывок не анализируется")
}

suite("InputBuffer: классификация символов") {
    expect(InputBuffer.isBufferable("a"), "латиница буферизуется")
    expect(InputBuffer.isBufferable("я"), "кириллица буферизуется")
    expect(InputBuffer.isBufferable(","), "запятая буферизуется (б)")
    expect(InputBuffer.isBufferable("["), "скобка буферизуется (х)")
    expect(InputBuffer.isBufferable("'"), "апостроф буферизуется (э)")
    expect(!InputBuffer.isBufferable("1"), "цифра не буферизуется")
    expect(!InputBuffer.isBufferable(" "), "пробел не буферизуется")
    expect(!InputBuffer.isBufferable("!"), "! не буферизуется")
}

// MARK: - Жесты Shift

func pressShift(_ d: ShiftGestureDetector, downAt: Double, upAt: Double) -> ShiftGesture {
    _ = d.handleFlagsChanged(keyCode: ShiftGestureDetector.leftShiftKeyCode, flags: .maskShift, time: downAt)
    return d.handleFlagsChanged(keyCode: ShiftGestureDetector.leftShiftKeyCode, flags: [], time: upAt)
}

suite("Double-Shift: распознавание жеста") {
    let d1 = ShiftGestureDetector(window: 0.4)
    expect(pressShift(d1, downAt: 0.0, upAt: 0.1) == .none, "первое нажатие не срабатывает")
    expect(pressShift(d1, downAt: 0.2, upAt: 0.3) == .double, "второе быстрое нажатие срабатывает")

    let d2 = ShiftGestureDetector(window: 0.4)
    _ = pressShift(d2, downAt: 0.0, upAt: 0.1)
    expect(pressShift(d2, downAt: 1.0, upAt: 1.1) == .none, "медленное второе нажатие не срабатывает")
    expect(pressShift(d2, downAt: 1.2, upAt: 1.3) == .double, "быстрое третье после второго срабатывает")

    let d3 = ShiftGestureDetector(window: 0.4)
    _ = pressShift(d3, downAt: 0.0, upAt: 0.1)
    d3.noteKeyDown()
    expect(pressShift(d3, downAt: 0.2, upAt: 0.3) == .none, "клавиша между нажатиями сбрасывает жест")
}

suite("Double-Shift: модификаторы и заглавные") {
    let shift = ShiftGestureDetector.leftShiftKeyCode

    let d1 = ShiftGestureDetector(window: 0.4)
    _ = d1.handleFlagsChanged(keyCode: shift, flags: .maskShift, time: 0.0)
    d1.noteKeyDown() // напечатали заглавную букву с зажатым Shift
    expect(d1.handleFlagsChanged(keyCode: shift, flags: [], time: 0.1) == .none, "Shift+буква не считается нажатием")
    expect(pressShift(d1, downAt: 0.2, upAt: 0.3) == .none, "следующее одиночное — первое, не второе")

    let d2 = ShiftGestureDetector(window: 0.4)
    _ = d2.handleFlagsChanged(keyCode: shift, flags: [.maskShift, .maskCommand], time: 0.0)
    _ = d2.handleFlagsChanged(keyCode: shift, flags: .maskCommand, time: 0.1)
    expect(pressShift(d2, downAt: 0.2, upAt: 0.3) == .none, "Cmd+Shift не считается жестом")
}

// MARK: - Фаза 2: статистический детектор, метрики, производительность

runPhase2Checks()
runProductChecks()

TestRunner.shared.finish()
