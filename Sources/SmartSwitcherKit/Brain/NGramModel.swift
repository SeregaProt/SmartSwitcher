import Foundation

/// Символьная языковая модель (FR-2): условные вероятности
/// P(c | ab) с интерполяцией к P(c | b).
///
/// Ресурс `<lang>_ngrams.tsv` содержит P(c|b) для биграмм и P(c|ab) для
/// триграмм, обученные на частотном корпусе; границы слова — `^^` и `$`.
/// Оценка слова — средний log10 P по всем позициям `^^слово$`.
/// Отложенная оценка (docs/DICTIONARIES.md): на словах вне словаря
/// триграммы ловят ~80% ошибок раскладки против ~50% у биграмм.
///
/// `@unchecked Sendable`: таблицы защищены `lock`.
public final class NGramModel: @unchecked Sendable {
    /// Вес триграммной части в интерполяции.
    public static let trigramWeight = 0.7
    /// Штраф за позицию, не встречавшуюся ни в одной n-грамме.
    public static let floorLogP = -6.0

    private struct Table {
        var bigrams: [String: Double] = [:]
        var trigrams: [String: Double] = [:]
    }

    private var tables: [Layout: Table] = [:]
    private let lock = NSLock()

    public init() {}

    public func warmUp() {
        for layout in Layout.allCases { _ = table(for: layout) }
    }

    /// Средний log10 P(символ | контекст) по слову (только буквы, lowercased).
    /// Возвращает nil для слов короче двух букв.
    public func score(_ word: String, in layout: Layout) -> Double? {
        let letters = word.lowercased().filter { $0.isLetter }
        guard letters.count >= 2 else { return nil }

        let model = table(for: layout)
        let chars = Array("^^" + letters + "$")
        var total = 0.0
        for i in 2..<chars.count {
            let p3 = model.trigrams[String(chars[(i - 2)...i])] ?? 0
            let p2 = model.bigrams[String(chars[(i - 1)...i])] ?? 0
            let p = Self.trigramWeight * p3 + (1 - Self.trigramWeight) * p2
            total += p > 0 ? log10(p) : Self.floorLogP
        }
        return total / Double(chars.count - 2)
    }

    private func table(for layout: Layout) -> Table {
        lock.lock()
        defer { lock.unlock() }
        if let cached = tables[layout] { return cached }

        var result = Table()
        if let url = Bundle.module.url(forResource: "\(layout.rawValue)_ngrams", withExtension: "tsv"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            for line in content.split(separator: "\n") {
                let parts = line.split(separator: "\t")
                guard parts.count == 2, let p = Double(parts[1]) else { continue }
                let key = String(parts[0])
                switch key.count {
                case 2: result.bigrams[key] = p
                case 3: result.trigrams[key] = p
                default: continue
                }
            }
            Log.brain.info("Модель \(layout.rawValue): \(result.bigrams.count) биграмм, \(result.trigrams.count) триграмм")
        } else {
            Log.brain.error("Ресурс n-грамм \(layout.rawValue) не найден")
        }
        tables[layout] = result
        return result
    }
}
