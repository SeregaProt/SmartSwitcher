import Foundation

/// Статистический детектор языка (фаза 2, FR-2) — основной «мозг».
///
/// Конвейер решения (precision-first, ТЗ 7.2):
/// 1. Стоп-листы — числа, URL, пути, идентификаторы → не трогать.
/// 2. Слово есть в словаре языка набранной раскладки → не трогать.
/// 3. Кандидат (конвертация в другую раскладку) есть в словаре другого
///    языка И статистически правдоподобнее исходника → исправить.
/// 4. Вне словарей: исправить только при резком статистическом перевесе
///    (исходник — явный «мусор», кандидат — словоподобен).
public final class StatisticalDetector: LanguageDetector {
    private let dictionaries: DictionaryService
    private let ngrams: NGramModel

    /// Исходник считается «мусором» ниже этого среднего log10 P.
    private let garbageCeiling: Double
    /// Кандидат должен быть словоподобнее этого порога.
    private let candidateFloor: Double
    /// Минимальный перевес кандидата над исходником (в порядках на биграмму).
    private let minAdvantage: Double
    /// Какие раскладки активны для исправления (Языки в настройках). Исправление
    /// в выключенную раскладку не выполняется. По умолчанию — все.
    private let enabledLayouts: () -> Set<Layout>

    public init(
        dictionaries: DictionaryService,
        ngrams: NGramModel,
        garbageCeiling: Double = -3.2,
        candidateFloor: Double = -2.6,
        minAdvantage: Double = 1.2,
        enabledLayouts: @escaping () -> Set<Layout> = { Set(Layout.allCases) }
    ) {
        self.dictionaries = dictionaries
        self.ngrams = ngrams
        self.garbageCeiling = garbageCeiling
        self.candidateFloor = candidateFloor
        self.minAdvantage = minAdvantage
        self.enabledLayouts = enabledLayouts
    }

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
        guard enabledLayouts().contains(target) else { return .keep }
        let core = TokenUtils.core(of: token).lowercased()
        guard core.count >= 2 else { return .keep }

        // 1. Осмысленное слово в наборной раскладке.
        if dictionaries.contains(core, in: source) { return .keep }

        // 2. Кандидат. Немаппируемое — не трогаем (graceful degradation).
        guard let converted = convert(token) else { return .keep }
        let convertedCore = TokenUtils.core(of: converted).lowercased()
        guard convertedCore.count >= 2 else { return .keep }

        guard let sourceScore = ngrams.score(core, in: source),
              let targetScore = ngrams.score(convertedCore, in: target) else {
            return .keep
        }

        // 3. Словарное слово другого языка — исправляем, если исходник
        //    не правдоподобнее кандидата.
        if dictionaries.contains(convertedCore, in: target) {
            return targetScore > sourceScore
                ? .correct(layout: target, replacement: converted)
                : .keep
        }

        // 4. Вне словарей — только при сильном статистическом сигнале.
        if sourceScore < garbageCeiling,
           targetScore > candidateFloor,
           targetScore - sourceScore > minAdvantage {
            return .correct(layout: target, replacement: converted)
        }

        return .keep
    }
}
