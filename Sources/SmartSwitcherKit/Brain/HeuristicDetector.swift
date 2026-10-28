import Foundation

/// Эвристический детектор языка (фаза 1, FR-2).
///
/// Комбинирует:
/// 1. Стоп-листы (числа, URL, пути, идентификаторы) — никогда не исправлять.
/// 2. Словари частотных слов — быстрый уверенный вердикт.
/// 3. Оценку «словоподобности»: частотные биграммы, гласные, длины
///    консонантных серий — для слов вне словаря.
///
/// Политика precision-first: исправляем только при высокой уверенности
/// (типичная цель precision > 98%, см. ТЗ 7.2).
public struct HeuristicDetector: LanguageDetector {
    /// Токен считается «мусором» в набранной раскладке ниже этого порога.
    private let garbageThreshold = 0.2
    /// Кандидат в другой раскладке должен быть словоподобен не ниже этого порога.
    private let candidateThreshold = 0.5

    public init() {}

    public func analyze(_ token: String) -> Verdict {
        guard token.count >= 2, token.count <= 32 else { return .keep }
        guard !StopRules.shouldIgnore(token) else { return .keep }

        switch TokenUtils.script(of: token) {
        case .latin:
            return analyze(token, typedIn: .en, convert: LayoutMapping.toRussian)
        case .cyrillic:
            return analyze(token, typedIn: .ru, convert: LayoutMapping.toEnglish)
        case .mixed, .none:
            return .keep
        }
    }

    private func analyze(
        _ token: String,
        typedIn source: Layout,
        convert: (String) -> String?
    ) -> Verdict {
        let target = source.other
        let core = TokenUtils.core(of: token).lowercased()
        guard core.count >= 2 else { return .keep }

        // 1. Слово существует в языке набранной раскладки — не трогаем.
        if LanguageData.words(for: source).contains(core) { return .keep }

        // 2. Кандидат в другой раскладке. Немаппируемые символы → не трогаем.
        guard let converted = convert(token) else { return .keep }
        let convertedCore = TokenUtils.core(of: converted).lowercased()
        guard convertedCore.count >= 2 else { return .keep }

        // 3. Кандидат — словарное слово другого языка: уверенное исправление.
        if LanguageData.words(for: target).contains(convertedCore) {
            return .correct(layout: target, replacement: converted)
        }

        // 4. Эвристика по словоподобности для слов вне словарей.
        let sourceScore = Self.wordlikeness(of: core, in: source)
        let targetScore = Self.wordlikeness(of: convertedCore, in: target)

        if sourceScore < garbageThreshold && targetScore >= candidateThreshold {
            return .correct(layout: target, replacement: converted)
        }

        // 5. Сильный сигнал: символы `[];` `` ` `` внутри латинского токена —
        //    в английских словах не встречаются, в RU-раскладке это буквы х ъ ж ё.
        if source == .en,
           token.contains(where: { "[];`".contains($0) }),
           targetScore >= 0.45, sourceScore < 0.45 {
            return .correct(layout: target, replacement: converted)
        }

        return .keep
    }

    /// Оценка 0...1: насколько строка похожа на слово языка `layout`.
    static func wordlikeness(of word: String, in layout: Layout) -> Double {
        let letters = word.lowercased().filter { $0.isLetter }
        guard letters.count >= 2 else { return 0.5 }

        let chars = Array(letters)
        let vowels = LanguageData.vowels(for: layout)
        let bigrams = LanguageData.bigrams(for: layout)

        var commonBigrams = 0
        for i in 0..<(chars.count - 1) {
            if bigrams.contains(String(chars[i...(i + 1)])) {
                commonBigrams += 1
            }
        }
        let bigramFraction = Double(commonBigrams) / Double(chars.count - 1)

        let hasVowel = chars.contains { vowels.contains($0) }
        var maxConsonantRun = 0
        var run = 0
        for ch in chars {
            if vowels.contains(ch) {
                run = 0
            } else {
                run += 1
                maxConsonantRun = max(maxConsonantRun, run)
            }
        }

        var score = 0.6 * bigramFraction
        score += hasVowel ? 0.2 : -0.35
        if maxConsonantRun >= 5 {
            score -= 0.3
        } else if maxConsonantRun <= 3 {
            score += 0.2
        }
        return min(1.0, max(0.0, score))
    }
}
