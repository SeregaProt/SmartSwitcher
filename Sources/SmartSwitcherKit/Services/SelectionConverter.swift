import AppKit

/// Преобразования выделенного текста по горячим клавишам (как в Punto):
/// сменить раскладку, инвертировать регистр, транслитерировать.
///
/// Текст берётся через буфер обмена (⌘C → преобразование → ⌘V); исходное
/// содержимое буфера восстанавливается. Работает только по явному действию
/// пользователя, текст никуда не сохраняется.
@MainActor
public final class SelectionConverter {
    public enum Transform {
        case layout
        case invertCase
        case transliterate
    }

    private enum KeyCode {
        static let c: CGKeyCode = 8
        static let v: CGKeyCode = 9
    }

    private let converter: LayoutConverting
    private let layouts: LayoutController
    private let stats: StatisticsService?
    private let source = CGEventSource(stateID: .combinedSessionState)
    private var isBusy = false

    public init(converter: LayoutConverting, layouts: LayoutController, stats: StatisticsService? = nil) {
        self.converter = converter
        self.layouts = layouts
        self.stats = stats
    }

    /// Выполнить преобразование над выделением активного приложения (главный поток).
    public func perform(_ transform: Transform) {
        guard !isBusy else { return }
        isBusy = true
        waitForModifiersRelease(deadline: Date().addingTimeInterval(1)) { [weak self] in
            self?.copySelection { text in
                guard let self else { return }
                defer { self.isBusy = false }
                guard let text, !text.isEmpty else { return }
                let output: String
                var target: Layout?
                switch transform {
                case .layout:
                    guard let converted = Self.convertLayout(text, converter: self.converter) else { return }
                    output = converted.text
                    target = converted.target
                case .invertCase:
                    output = Self.invertCase(text)
                case .transliterate:
                    output = Self.transliterate(text)
                }
                guard output != text else { return }
                self.paste(output)
                if let target { self.layouts.select(target) }
                self.stats?.record(.manual)
            }
        }
    }

    // MARK: - Чистые преобразования (покрыты тестами)

    /// Конвертация в «другую» раскладку по преобладающей письменности.
    public nonisolated static func convertLayout(_ text: String, converter: LayoutConverting) -> (text: String, target: Layout)? {
        let latin = text.filter(TokenUtils.isLatinLetter).count
        let cyrillic = text.filter(TokenUtils.isCyrillicLetter).count
        guard latin + cyrillic > 0 else { return nil }
        let source: Layout = latin >= cyrillic ? .en : .ru
        let target = source.other
        return (converter.convertLenient(text, from: source, to: target), target)
    }

    public nonisolated static func invertCase(_ text: String) -> String {
        String(text.map { ch -> String in
            let s = String(ch)
            if ch.isUppercase { return s.lowercased() }
            if ch.isLowercase { return s.uppercased() }
            return s
        }.joined())
    }

    private nonisolated static let cyrillicToLatin: [Character: String] = [
        "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "yo",
        "ж": "zh", "з": "z", "и": "i", "й": "y", "к": "k", "л": "l", "м": "m",
        "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u",
        "ф": "f", "х": "kh", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "shch",
        "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya",
    ]

    /// Латиница → кириллица: сначала длинные сочетания.
    private nonisolated static let latinToCyrillic: [(String, String)] = [
        ("shch", "щ"), ("zh", "ж"), ("kh", "х"), ("ts", "ц"), ("ch", "ч"),
        ("sh", "ш"), ("yo", "ё"), ("yu", "ю"), ("ya", "я"),
        ("a", "а"), ("b", "б"), ("v", "в"), ("g", "г"), ("d", "д"), ("e", "е"),
        ("z", "з"), ("i", "и"), ("y", "й"), ("k", "к"), ("l", "л"), ("m", "м"),
        ("n", "н"), ("o", "о"), ("p", "п"), ("r", "р"), ("s", "с"), ("t", "т"),
        ("u", "у"), ("f", "ф"), ("h", "х"), ("c", "ц"), ("w", "в"), ("x", "кс"),
        ("j", "дж"), ("q", "к"),
    ]

    /// Транслитерация в обе стороны по преобладающей письменности.
    public nonisolated static func transliterate(_ text: String) -> String {
        let latin = text.filter(TokenUtils.isLatinLetter).count
        let cyrillic = text.filter(TokenUtils.isCyrillicLetter).count
        if cyrillic >= latin {
            return text.map { ch -> String in
                let lower = Character(ch.lowercased())
                guard let mapped = cyrillicToLatin[lower] else { return String(ch) }
                return ch.isUppercase ? mapped.prefix(1).uppercased() + mapped.dropFirst() : mapped
            }.joined()
        }
        var result = ""
        var rest = Substring(text)
        outer: while let first = rest.first {
            for (latinPart, cyr) in latinToCyrillic where rest.lowercased().hasPrefix(latinPart) {
                let original = rest.prefix(latinPart.count)
                result += original.first?.isUppercase == true ? cyr.uppercased() : cyr
                rest = rest.dropFirst(latinPart.count)
                continue outer
            }
            result.append(first)
            rest = rest.dropFirst()
        }
        return result
    }

    // MARK: - Буфер обмена

    /// Хоткей срабатывает при зажатых ⌃⌥ — синтетический ⌘C с ними превратился
    /// бы в ⌃⌥⌘C, поэтому ждём отпускания модификаторов.
    private func waitForModifiersRelease(deadline: Date, then action: @escaping () -> Void) {
        let held = NSEvent.modifierFlags.intersection([.control, .option, .command, .shift])
        if held.isEmpty || Date() > deadline {
            action()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            self?.waitForModifiersRelease(deadline: deadline, then: action)
        }
    }

    private func copySelection(completion: @escaping (String?) -> Void) {
        let pasteboard = NSPasteboard.general
        let saved = Self.snapshot(of: pasteboard)
        let before = pasteboard.changeCount
        postCommand(KeyCode.c)
        pollPasteboard(before: before, attempts: 15) { changed in
            let text = changed ? pasteboard.string(forType: .string) : nil
            completion(text)
            // Возвращаем пользователю его буфер обмена после вставки.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                Self.restore(saved, to: pasteboard)
            }
        }
    }

    private func pollPasteboard(before: Int, attempts: Int, completion: @escaping (Bool) -> Void) {
        if NSPasteboard.general.changeCount != before {
            completion(true)
        } else if attempts <= 0 {
            completion(false)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                self?.pollPasteboard(before: before, attempts: attempts - 1, completion: completion)
            }
        }
    }

    private func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        postCommand(KeyCode.v)
    }

    private func postCommand(_ keyCode: CGKeyCode) {
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else {
                continue
            }
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: TextReplacer.injectionMarker)
            event.post(tap: .cghidEventTap)
        }
    }

    private static func snapshot(of pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var entry: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { entry[type] = data }
            }
            return entry
        }
    }

    private static func restore(_ items: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let restored = items.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entry { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}
