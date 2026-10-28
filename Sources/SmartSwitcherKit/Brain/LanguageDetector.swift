/// Вердикт детектора по набранному токену.
public enum Verdict: Equatable, Sendable {
    /// Не трогать ввод.
    case keep
    /// Исправить: переключиться на раскладку `layout`, заменить токен на `replacement`.
    case correct(layout: Layout, replacement: String)
}

/// «Мозг» приложения — заменяемый компонент (см. архитектуру в ТЗ, раздел 3).
/// Фаза 1 — эвристика; фаза 2 — n-gram модель за тем же протоколом.
public protocol LanguageDetector {
    func analyze(_ token: String) -> Verdict
}

/// Утилиты работы с токеном.
public enum TokenUtils {
    private static let edgePunctuation = Set<Character>(",.!?;:'\"«»()[]{}")

    /// «Ядро» токена — без пунктуации по краям (для проверок по словарю).
    public static func core(of token: String) -> String {
        var s = Substring(token)
        while let f = s.first, edgePunctuation.contains(f) { s = s.dropFirst() }
        while let l = s.last, edgePunctuation.contains(l) { s = s.dropLast() }
        return String(s)
    }

    public static func isLatinLetter(_ ch: Character) -> Bool {
        ("a"..."z").contains(ch) || ("A"..."Z").contains(ch)
    }

    public static func isCyrillicLetter(_ ch: Character) -> Bool {
        guard let scalar = ch.unicodeScalars.first, ch.unicodeScalars.count == 1 else { return false }
        return (0x0400...0x04FF).contains(scalar.value)
    }

    /// Определяет письменность токена по буквам (пунктуация нейтральна).
    public enum Script { case latin, cyrillic, mixed, none }

    public static func script(of token: String) -> Script {
        var hasLatin = false
        var hasCyrillic = false
        for ch in token {
            if isLatinLetter(ch) { hasLatin = true }
            else if isCyrillicLetter(ch) { hasCyrillic = true }
        }
        switch (hasLatin, hasCyrillic) {
        case (true, false): return .latin
        case (false, true): return .cyrillic
        case (true, true): return .mixed
        case (false, false): return .none
        }
    }
}
