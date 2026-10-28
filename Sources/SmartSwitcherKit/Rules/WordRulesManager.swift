import Foundation

/// Пользовательские правила по словам (FR-5):
/// - `neverCorrect` — слова, которые никогда не исправляются (имена, термины,
///   команды); сюда же пишет самообучение (FR-6).
/// - `alwaysCorrect` — слова, которые исправляются всегда, минуя детектор.
///
/// Чтение — из потокобезопасного снимка (движок на фоновой очереди),
/// запись — на главном потоке.
public final class WordRulesManager {
    private let preferences: Preferences

    public init(preferences: Preferences) {
        self.preferences = preferences
    }

    public func isNeverCorrect(_ word: String) -> Bool {
        preferences.engine.neverCorrectWords.contains(Self.normalize(word))
    }

    public func isAlwaysCorrect(_ word: String) -> Bool {
        preferences.engine.alwaysCorrectWords.contains(Self.normalize(word))
    }

    public func addNeverCorrect(_ word: String) {
        let normalized = Self.normalize(word)
        guard !normalized.isEmpty else { return }
        DispatchQueue.main.async { [preferences] in
            if !preferences.neverCorrectWords.contains(normalized) {
                preferences.neverCorrectWords.append(normalized)
            }
        }
    }

    public func addAlwaysCorrect(_ word: String) {
        let normalized = Self.normalize(word)
        guard !normalized.isEmpty else { return }
        DispatchQueue.main.async { [preferences] in
            if !preferences.alwaysCorrectWords.contains(normalized) {
                preferences.alwaysCorrectWords.append(normalized)
            }
        }
    }

    public static func normalize(_ word: String) -> String {
        TokenUtils.core(of: word.trimmingCharacters(in: .whitespacesAndNewlines)).lowercased()
    }
}
