import Foundation

/// Автозамена и расширения текста (FR-7): пользовательские правила
/// «сокращение → развёрнутый текст». Срабатывает на границе слова, до
/// детектора раскладки. Сравнение по нормализованному ядру слова.
public final class TextExpander {
    private let preferences: Preferences

    public init(preferences: Preferences) {
        self.preferences = preferences
    }

    /// Возвращает развёрнутый текст для сокращения, если правило есть и функция
    /// включена. Сохраняет регистр: ВСЁ-КАПСОМ и Сначала-Заглавная.
    public func expansion(for token: String) -> String? {
        guard preferences.textExpansionEnabled else { return nil }
        let core = TokenUtils.core(of: token)
        let key = core.lowercased()
        guard !key.isEmpty, let value = preferences.expansionRules[key] else { return nil }
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
