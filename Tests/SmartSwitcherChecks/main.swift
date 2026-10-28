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

// MARK: - HeuristicDetector

let detector = HeuristicDetector()

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
        expect(
            detector.analyze(input) == .correct(layout: .ru, replacement: expected),
            "\(input) → \(expected), получено: \(detector.analyze(input))"
        )
    }
}

suite("Детектор: английский мусор в RU-раскладке исправляется") {
    let corrections: [(String, String)] = [
        ("руддщ", "hello"),
        ("еру", "the"),
        ("цщкв", "word"),
        ("ьфс", "mac"),
        ("руддщб", "hello,"),
    ]
    for (input, expected) in corrections {
        expect(
            detector.analyze(input) == .correct(layout: .en, replacement: expected),
            "\(input) → \(expected), получено: \(detector.analyze(input))"
        )
    }
}

suite("Детектор: нормальные слова не трогаются (precision)") {
    let words = [
        "hello", "the", "world", "swift", "mac", "don't", "qwerty",
        "btw", "really", "code", "github",
        "привет", "спасибо", "мама", "слово", "работа", "сегодня",
        "Привет", "файл", "огурец", "программа",
    ]
    for word in words {
        expect(detector.analyze(word) == .keep, "не трогать: \(word), получено: \(detector.analyze(word))")
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
        expect(detector.analyze(token) == .keep, "стоп-лист: \(token)")
    }
}

suite("Детектор: граничные случаи") {
    expect(detector.analyze("a") == .keep, "одиночная буква EN")
    expect(detector.analyze("я") == .keep, "одиночная буква RU")
    expect(detector.analyze(String(repeating: "f", count: 40)) == .keep, "сверхдлинный токен")
    expect(detector.analyze("abcабв") == .keep, "смешанная письменность")
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

    let cleared = InputBuffer()
    cleared.append("a")
    cleared.append("1")
    cleared.backspace()
    expect(cleared.current.isEmpty && !cleared.isTainted, "полное стирание снимает таинт")
}

suite("InputBuffer: переполнение и сброс") {
    let buffer = InputBuffer()
    for _ in 0..<(InputBuffer.maxLength + 5) { buffer.append("a") }
    expect(buffer.isTainted, "переполнение → таинт")

    let kept = InputBuffer()
    for ch in "word" { kept.append(ch) }
    kept.commit(separator: " ")
    kept.append("x")
    kept.reset()
    expect(kept.lastCommitted?.word == "word", "reset не трогает lastCommitted")
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

// MARK: - DoubleShiftDetector

func press(_ d: DoubleShiftDetector, downAt: Double, upAt: Double) -> Bool {
    _ = d.handleFlagsChanged(
        keyCode: DoubleShiftDetector.leftShiftKeyCode,
        flags: .maskShift,
        time: downAt
    )
    return d.handleFlagsChanged(
        keyCode: DoubleShiftDetector.leftShiftKeyCode,
        flags: [],
        time: upAt
    )
}

suite("Double-Shift: распознавание жеста") {
    let d1 = DoubleShiftDetector(window: 0.4)
    expect(!press(d1, downAt: 0.0, upAt: 0.1), "первое нажатие не срабатывает")
    expect(press(d1, downAt: 0.2, upAt: 0.3), "второе быстрое нажатие срабатывает")

    let d2 = DoubleShiftDetector(window: 0.4)
    _ = press(d2, downAt: 0.0, upAt: 0.1)
    expect(!press(d2, downAt: 1.0, upAt: 1.1), "медленное второе нажатие не срабатывает")
    expect(press(d2, downAt: 1.2, upAt: 1.3), "быстрое третье после второго срабатывает")

    let d3 = DoubleShiftDetector(window: 0.4)
    _ = press(d3, downAt: 0.0, upAt: 0.1)
    d3.noteKeyDown()
    expect(!press(d3, downAt: 0.2, upAt: 0.3), "клавиша между нажатиями сбрасывает жест")
}

suite("Double-Shift: модификаторы и заглавные") {
    let shift = DoubleShiftDetector.leftShiftKeyCode

    let d1 = DoubleShiftDetector(window: 0.4)
    _ = d1.handleFlagsChanged(keyCode: shift, flags: .maskShift, time: 0.0)
    d1.noteKeyDown() // напечатали заглавную букву с зажатым Shift
    expect(
        !d1.handleFlagsChanged(keyCode: shift, flags: [], time: 0.1),
        "Shift+буква не считается нажатием"
    )
    expect(!press(d1, downAt: 0.2, upAt: 0.3), "следующее одиночное — первое, не второе")

    let d2 = DoubleShiftDetector(window: 0.4)
    _ = d2.handleFlagsChanged(keyCode: shift, flags: [.maskShift, .maskCommand], time: 0.0)
    _ = d2.handleFlagsChanged(keyCode: shift, flags: .maskCommand, time: 0.1)
    expect(!press(d2, downAt: 0.2, upAt: 0.3), "Cmd+Shift не считается жестом")
}

// MARK: - Фаза 2: статистический детектор, метрики, производительность

runPhase2Checks()

TestRunner.shared.finish()
