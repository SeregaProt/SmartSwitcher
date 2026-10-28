import Foundation

/// Словари частотных слов (фаза 2, FR-2). Загружаются лениво из ресурсов
/// бандла (top-9000 на язык из корпуса OpenSubtitles, hermitdave/FrequencyWords,
/// CC-BY-SA — см. docs/DICTIONARIES.md).
///
/// `@unchecked Sendable`: кеш защищён `lock`.
public final class DictionaryService: @unchecked Sendable {
    private var cache: [Layout: Set<String>] = [:]
    private let lock = NSLock()

    public init() {}

    /// Предзагрузка вне горячего пути (вызывается при старте в фоне).
    public func warmUp() {
        _ = words(for: .en)
        _ = words(for: .ru)
    }

    public func contains(_ word: String, in layout: Layout) -> Bool {
        words(for: layout).contains(word)
    }

    public func words(for layout: Layout) -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[layout] { return cached }

        let resource = layout == .en ? "en_words" : "ru_words"
        var result: Set<String>
        if let url = Bundle.module.url(forResource: resource, withExtension: "txt"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            result = Set(content.split(separator: "\n").map(String.init))
            Log.brain.info("Словарь \(layout.rawValue): \(result.count) слов")
        } else {
            // Graceful degradation: без ресурсов работаем на встроенном мини-словаре.
            result = LanguageData.words(for: layout)
            Log.brain.error("Ресурс словаря \(layout.rawValue) не найден, используется встроенный мини-словарь")
        }
        cache[layout] = result
        return result
    }
}
