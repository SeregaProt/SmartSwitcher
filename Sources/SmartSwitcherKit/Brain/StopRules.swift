import Foundation

/// Стоп-листы (FR-2): токены, которые детектор не должен трогать никогда.
/// Приоритет precision над recall — при сомнении пропускаем.
public enum StopRules {
    private static let domainTLDs: Set<String> = [
        "com", "ru", "org", "net", "io", "dev", "app", "me", "co", "info",
        "biz", "gov", "edu", "ua", "by", "kz", "uk", "de", "fr", "json",
        "html", "css", "js", "ts", "swift", "py", "md", "txt", "pdf", "png",
        "jpg", "jpeg", "gif", "zip", "yml", "yaml", "xml", "sh", "log",
    ]

    public static func shouldIgnore(_ token: String) -> Bool {
        guard !token.isEmpty else { return true }

        // Числа, версии, идентификаторы с цифрами.
        if token.contains(where: { $0.isNumber }) { return true }

        let lower = token.lowercased()

        // URL, e-mail, пути.
        if lower.contains("://") || lower.contains("www.") { return true }
        if token.contains("@") || token.contains("\\") { return true }
        if token.hasPrefix("/") || token.hasPrefix("~") || token.hasPrefix("-")
            || token.hasPrefix("#") || token.hasPrefix("$") || token.hasPrefix("--") {
            return true
        }

        // Домены и имена файлов: word.tld
        if looksLikeDomainOrFile(lower) { return true }

        // Идентификаторы: snake_case, camelCase, АББРЕВИАТУРЫ.
        if token.contains("_") { return true }
        let letters = token.filter { $0.isLetter }
        if letters.count >= 2 {
            if letters.allSatisfy({ $0.isUppercase }) { return true }
            // Заглавная внутри слова (не первая буква) — camelCase / McDonald.
            if letters.dropFirst().contains(where: { $0.isUppercase }) { return true }
        }

        return false
    }

    private static func looksLikeDomainOrFile(_ lower: String) -> Bool {
        let parts = lower.split(separator: ".")
        guard parts.count >= 2, let last = parts.last else { return false }
        return domainTLDs.contains(String(last))
            && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { ch in ch.isLetter || ch.isNumber || ch == "-" } }
    }
}
