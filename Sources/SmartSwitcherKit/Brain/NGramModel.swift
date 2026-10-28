import Foundation

/// Частотная биграммная модель языка (фаза 2, FR-2).
///
/// Хранит log10-вероятности биграмм, включая маркеры границ слова
/// (`^` — начало, `$` — конец), обученные на частотном корпусе.
/// Оценка слова — средний log10 P(биграмма) по всем биграммам `^слово$`.
/// Невиданная биграмма получает штраф `floorLogP` — для типичного «мусора»
/// чужой раскладки таких биграмм много, и оценка резко падает.
public final class NGramModel {
    public static let floorLogP = -6.5

    private var tables: [Layout: [String: Double]] = [:]
    private let lock = NSLock()

    public init() {}

    public func warmUp() {
        _ = table(for: .en)
        _ = table(for: .ru)
    }

    /// Средняя log10-вероятность биграмм слова (только буквы, lowercased).
    /// Возвращает nil, если в слове меньше одной биграммы.
    public func score(_ word: String, in layout: Layout) -> Double? {
        let letters = word.lowercased().filter { $0.isLetter }
        guard letters.count >= 2 else { return nil }

        let model = table(for: layout)
        let marked = "^" + letters + "$"
        let chars = Array(marked)
        var total = 0.0
        for i in 0..<(chars.count - 1) {
            let bigram = String(chars[i...(i + 1)])
            total += model[bigram] ?? Self.floorLogP
        }
        return total / Double(chars.count - 1)
    }

    private func table(for layout: Layout) -> [String: Double] {
        lock.lock()
        defer { lock.unlock() }
        if let cached = tables[layout] { return cached }

        let resource = layout == .en ? "en_bigrams" : "ru_bigrams"
        var result: [String: Double] = [:]
        if let url = Bundle.module.url(forResource: resource, withExtension: "tsv"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            for line in content.split(separator: "\n") {
                let parts = line.split(separator: "\t")
                guard parts.count == 2, let logP = Double(parts[1]) else { continue }
                result[String(parts[0])] = logP
            }
            Log.brain.info("Биграммная модель \(layout.rawValue): \(result.count) биграмм")
        } else {
            Log.brain.error("Ресурс биграмм \(layout.rawValue) не найден")
        }
        tables[layout] = result
        return result
    }
}
