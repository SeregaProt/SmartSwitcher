import Foundation

/// Автозамена и расширения текста (FR-7, план Pro): пользовательские правила
/// «сокращение → развёрнутый текст». Срабатывает на границе слова, до
/// детектора раскладки. Сравнение по нормализованному ядру слова.
public final class TextExpander {
    private let preferences: Preferences

    public init(preferences: Preferences) {
        self.preferences = preferences
    }

    /// Возвращает развёрнутый текст для сокращения, если правило есть и функция
    /// доступна. Сохраняет регистр: ВСЁ-КАПСОМ и Сначала-Заглавная.
    /// Потокобезопасно: читает снимок настроек.
    public func expansion(for token: String) -> String? {
        let settings = preferences.engine
        guard settings.expansionAvailable else { return nil }
        let core = TokenUtils.core(of: token)
        let key = core.lowercased()
        guard !key.isEmpty, let value = settings.expansionRules[key] else { return nil }
        return applyCase(of: core, to: value)
    }

    private func applyCase(of source: String, to target: String) -> String {
        guard let first = source.first else { return target }
        if source.count > 1, source.allSatisfy({ $0.isUppercase || !$0.isLetter }) {
            return target.uppercased()
        }
        if first.isUppercase {
            return target.prefix(1).uppercased() + target.dropFirst()
        }
        return target
    }
}
