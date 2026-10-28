import Foundation

/// Статистический детектор языка (FR-2) — основной «мозг».
///
/// Конвейер решения (precision-first, ТЗ 7.2):
/// 1. Стоп-листы — числа, URL, пути, идентификаторы → не трогать.
/// 2. Слово есть в словаре (общем или личном) языка набранной раскладки → не трогать.
/// 3. Кандидат (те же клавиши в другой раскладке) есть в словаре другого
///    языка И статистически правдоподобнее исходника → исправить.
/// 4. Вне словарей: исправить только при резком статистическом перевесе
///    (исходник — явный «мусор», кандидат — словоподобен). Если предыдущие
///    слова фразы на языке кандидата, пороги чуть мягче.
///
/// Пороги подобраны на отложенной выборке (docs/DICTIONARIES.md):
/// ложные срабатывания вне словаря ≤ 0.25%, в контексте ≤ 0.35%.
public final class StatisticalDetector: LanguageDetector {
    public struct Thresholds: Sendable {
        /// Исходник считается «мусором» ниже этой средней log10 P.
        public var garbageCeiling: Double
        /// Кандидат должен быть словоподобнее этого порога.
        public var candidateFloor: Double
        /// Минимальный перевес кандидата над исходником.
        public var minAdvantage: Double

        public static let strict = Thresholds(garbageCeiling: -1.4, candidateFloor: -1.4, minAdvantage: 0.4)
        public static let contextual = Thresholds(garbageCeiling: -1.3, candidateFloor: -1.5, minAdvantage: 0.3)
    }

    /// Однобуквенные слова: исправляются только при поддержке контекста.
    private static let singleLetterWords: [Layout: Set<String>] = [
        .ru: ["в", "и", "к", "с", "у", "о", "а", "я"],
        .en: ["a", "i"],
    ]

    private let dictionaries: DictionaryService
    private let ngrams: NGramModel
    private let converter: LayoutConverting
    private let personal: PersonalDictionary?
    private let strict: Thresholds
    private let contextual: Thresholds
    /// Какие раскладки активны для исправления (Языки в настройках).
    private let enabledLayouts: () -> Set<Layout>

    public init(
        dictionaries: DictionaryService,
        ngrams: NGramModel,
        converter: LayoutConverting = StaticLayoutConverter(),
        personal: PersonalDictionary? = nil,
        strict: Thresholds = .strict,
        contextual: Thresholds = .contextual,
        enabledLayouts: @escaping () -> Set<Layout> = { Set(Layout.allCases) }
    ) {
        self.dictionaries = dictionaries
        self.ngrams = ngrams
        self.converter = converter
        self.personal = personal
        self.strict = strict
        self.contextual = contextual
        self.enabledLayouts = enabledLayouts
    }

    public func analyze(_ token: String, context: DetectionContext) -> Verdict {
        guard !token.isEmpty, token.count <= InputBuffer.maxLength else { return .keep }

        // Caps Lock: ЗАГЛАВНЫЕ набраны капсом, а не как аббревиатура —
        // анализируем строчную форму и возвращаем ответ тоже капсом.
        if context.capsLock, Self.isAllCaps(token) {
            var plain = context
            plain.capsLock = false
            if case let .correct(layout, replacement) = analyze(token.lowercased(), context: plain) {
                return .correct(layout: layout, replacement: replacement.uppercased())
            }
            return .keep
        }

        guard !StopRules.shouldIgnore(token) else { return .keep }

        let source: Layout
        switch TokenUtils.script(of: token) {
        case .latin: source = .en
        case .cyrillic: source = .ru
        case .mixed, .none: return .keep
        }
        let target = source.other
        guard enabledLayouts().contains(target) else { return .keep }

        let core = TokenUtils.core(of: token).lowercased()
        if core.count == 1 {
            return analyzeSingleLetter(token, core: core, source: source, target: target, context: context)
        }
        guard core.count >= 2 else { return .keep }

        // 1. Осмысленное слово в наборной раскладке.
        if isKnown(core, in: source) { return .keep }

        // 2. Кандидат. Немаппируемое — не трогаем (graceful degradation).
        guard let converted = converter.convert(token, from: source, to: target) else { return .keep }
        let convertedCore = TokenUtils.core(of: converted).lowercased()
        guard convertedCore.count >= 2 else { return .keep }

        guard let sourceScore = ngrams.score(core, in: source),
              let targetScore = ngrams.score(convertedCore, in: target) else {
            return .keep
        }

        // 3. Словарное слово другого языка — исправляем, если исходник
        //    не правдоподобнее кандидата.
        if isKnown(convertedCore, in: target) {
            return targetScore > sourceScore
                ? .correct(layout: target, replacement: converted)
                : .keep
        }

        // 4. Вне словарей — только при сильном статистическом сигнале.
        let t = context.previousLanguage == target ? contextual : strict
        if sourceScore < t.garbageCeiling,
           targetScore > t.candidateFloor,
           targetScore - sourceScore > t.minAdvantage {
            return .correct(layout: target, replacement: converted)
        }
        return .keep
    }

    // MARK: - Private

    private func isKnown(_ word: String, in layout: Layout) -> Bool {
        dictionaries.contains(word, in: layout) || (personal?.contains(word, in: layout) ?? false)
    }

    /// «d» после русских слов — это «в»; без контекста одна буква неоднозначна.
    private func analyzeSingleLetter(
        _ token: String,
        core: String,
        source: Layout,
        target: Layout,
        context: DetectionContext
    ) -> Verdict {
        guard context.previousLanguage == target,
              !(Self.singleLetterWords[source]?.contains(core) ?? false),
              let converted = converter.convert(token, from: source, to: target) else {
            return .keep
        }
        let convertedCore = TokenUtils.core(of: converted).lowercased()
        guard convertedCore.count == 1,
              Self.singleLetterWords[target]?.contains(convertedCore) ?? false else {
            return .keep
        }
        return .correct(layout: target, replacement: converted)
    }

    private static func isAllCaps(_ token: String) -> Bool {
        let letters = token.filter { $0.isLetter }
        return !letters.isEmpty && letters.allSatisfy { $0.isUppercase }
    }
}
