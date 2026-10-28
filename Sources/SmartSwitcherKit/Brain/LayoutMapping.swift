/// Посимвольный маппинг US QWERTY ↔ русская ЙЦУКЕН (стандартные macOS-раскладки).
/// Используется детектором для построения «кандидата» слова в другой раскладке
/// и заменителем текста для перенабора.
public enum LayoutMapping {
    /// Пары (латиница, кириллица) для нижнего регистра. Верхний регистр строится автоматически.
    private static let lowerPairs: [(Character, Character)] = [
        ("q", "й"), ("w", "ц"), ("e", "у"), ("r", "к"), ("t", "е"),
        ("y", "н"), ("u", "г"), ("i", "ш"), ("o", "щ"), ("p", "з"),
        ("[", "х"), ("]", "ъ"),
        ("a", "ф"), ("s", "ы"), ("d", "в"), ("f", "а"), ("g", "п"),
        ("h", "р"), ("j", "о"), ("k", "л"), ("l", "д"),
        (";", "ж"), ("'", "э"),
        ("z", "я"), ("x", "ч"), ("c", "с"), ("v", "м"), ("b", "и"),
        ("n", "т"), ("m", "ь"),
        (",", "б"), (".", "ю"), ("/", "."), ("`", "ё"),
    ]

    /// Символы, доступные только через Shift.
    private static let shiftedPairs: [(Character, Character)] = [
        ("{", "Х"), ("}", "Ъ"), (":", "Ж"), ("\"", "Э"),
        ("<", "Б"), (">", "Ю"), ("?", ","), ("~", "Ё"),
        ("@", "\""), ("#", "№"), ("$", ";"), ("^", ":"), ("&", "?"),
    ]

    public static let enToRuTable: [Character: Character] = {
        var map: [Character: Character] = [:]
        for (en, ru) in lowerPairs {
            map[en] = ru
            if en.isLetter, ru.isLetter,
               let enUp = String(en).uppercased().first,
               let ruUp = String(ru).uppercased().first {
                map[enUp] = ruUp
            }
        }
        for (en, ru) in shiftedPairs {
            map[en] = ru
        }
        return map
    }()

    public static let ruToEnTable: [Character: Character] = {
        var map: [Character: Character] = [:]
        for (en, ru) in lowerPairs {
            map[ru] = en
            if en.isLetter, ru.isLetter,
               let enUp = String(en).uppercased().first,
               let ruUp = String(ru).uppercased().first {
                map[ruUp] = enUp
            }
        }
        // Обратные соответствия для shift-символов, где они однозначны.
        map[","] = "?"
        map["№"] = "#"
        map["Э"] = "\""
        return map
    }()

    /// Конвертирует строку из EN-раскладки в RU. Возвращает nil, если встретился
    /// немаппируемый символ (graceful degradation — не трогаем ввод).
    public static func toRussian(_ text: String) -> String? {
        convert(text, with: enToRuTable)
    }

    /// Конвертирует строку из RU-раскладки в EN.
    public static func toEnglish(_ text: String) -> String? {
        convert(text, with: ruToEnTable)
    }

    private static func convert(_ text: String, with table: [Character: Character]) -> String? {
        var result = ""
        result.reserveCapacity(text.count)
        for ch in text {
            guard let mapped = table[ch] else { return nil }
            result.append(mapped)
        }
        return result
    }
}
