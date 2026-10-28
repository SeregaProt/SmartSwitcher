/// Буфер текущего «слова» (FR-1). Накапливает символы до разделителя,
/// отслеживает «загрязнение» (цифры, спецсимволы, переполнение) — такие
/// токены анализу не подлежат.
public final class InputBuffer {
    public static let maxLength = 32

    /// Символы, буферизуемые как потенциальные буквы: латиница, кириллица
    /// и пунктуация, которая в другой раскладке является буквой (ж э х ъ б ю ё и т.п.).
    private static let mappablePunctuation = Set<Character>(",.;'`[]/?<>:\"{}~")

    public private(set) var current: String = ""
    public private(set) var isTainted = false

    /// Последний закоммиченный токен и его разделитель — для Double-Shift.
    public private(set) var lastCommitted: (word: String, separator: String)?

    public init() {}

    public static func isBufferable(_ ch: Character) -> Bool {
        TokenUtils.isLatinLetter(ch) || TokenUtils.isCyrillicLetter(ch)
            || mappablePunctuation.contains(ch)
    }

    public func append(_ ch: Character) {
        guard current.count < Self.maxLength else {
            isTainted = true
            return
        }
        if Self.isBufferable(ch) {
            current.append(ch)
        } else {
            isTainted = true
        }
    }

    public func taint() {
        isTainted = true
    }

    public func backspace() {
        if !current.isEmpty {
            current.removeLast()
        }
        if current.isEmpty {
            isTainted = false
        }
    }

    /// Сброс при потере контекста курсора (клик мыши, стрелки, Esc, Cmd-комбинации).
    public func reset() {
        current = ""
        isTainted = false
    }

    /// Фиксация слова по разделителю. Возвращает чистый токен или nil,
    /// если буфер пуст/загрязнён. Буфер очищается в любом случае.
    @discardableResult
    public func commit(separator: String) -> String? {
        defer { reset() }
        guard !current.isEmpty, !isTainted else { return nil }
        let word = current
        lastCommitted = (word, separator)
        return word
    }

    /// Обновить «последнее слово» после авто-исправления, чтобы Double-Shift
    /// мог откатить замену.
    public func setLastCommitted(word: String, separator: String) {
        lastCommitted = (word, separator)
    }

    /// Заменить текущее (ещё не закоммиченное) слово после ручной конвертации.
    public func replaceCurrent(with text: String) {
        current = text
        isTainted = false
    }
}
