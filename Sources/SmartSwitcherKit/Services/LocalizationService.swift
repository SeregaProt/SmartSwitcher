import Foundation

/// Локализация интерфейса (раздел 18 ТЗ). Строки — в Resources/<lang>.lproj.
/// Языки детекта раскладок — отдельная подсистема и не зависят от языка UI.
public enum L10n {
    /// Возвращает локализованную строку; `fallback` — русский текст по умолчанию
    /// (используется и как value при отсутствии перевода).
    public static func text(_ key: String, _ fallback: String) -> String {
        NSLocalizedString(key, bundle: .module, value: fallback, comment: "")
    }
}
