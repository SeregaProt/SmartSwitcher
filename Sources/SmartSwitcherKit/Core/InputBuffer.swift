/// Буфер текущего «слова» (FR-1). Хранит ВСЕ символы, набранные с момента
/// последней границы слова, — так Backspace всегда синхронен с экраном.
/// Токен «загрязнён» (анализу не подлежит), если в нём есть немаппируемые
/// символы (цифры, спецсимволы), он переполнен или после правки вслепую.
public final class InputBuffer {
    public static let maxLength = 32

    /// Пунктуация, которая в другой раскладке является буквой (ж э х ъ б ю ё и т.п.).
    private static let mappablePunctuation = Set<Character>(",.;'`[]/?<>:\"{}~")

    private var raw: [Character] = []
    /// Переполнение или правка за пределами известного текста — до коммита/сброса.
    private var isBroken = false
    private let isMappable: (Character) -> Bool

    /// Последний закоммиченный токен и его разделитель — для Double-Shift.
    /// nil, если позиция курсора относительно слова больше не известна.
    public private(set) var lastCommitted: (word: String, separator: String)?

    /// - Parameter isMappable: может ли символ быть частью слова (по умолчанию —
    ///   латиница, кириллица и пунктуация-буквы стандартных раскладок).
    public init(isMappable: @escaping (Character) -> Bool = InputBuffer.isBufferable) {
        self.isMappable = isMappable
    }

    public var current: String { String(raw) }

    public var isTainted: Bool {
        isBroken || raw.contains { !isMappable($0) }
    }

    public static func isBufferable(_ ch: Character) -> Bool {
        TokenUtils.isLatinLetter(ch) || TokenUtils.isCyrillicLetter(ch)
            || mappablePunctuation.contains(ch)
    }

    public func append(_ ch: Character) {
        guard raw.count < Self.maxLength else {
            isBroken = true
            return
        }
        raw.append(ch)
    }

    public func taint() {
        isBroken = true
    }

    public func backspace() {
        if !raw.isEmpty {
            raw.removeLast()
            return
        }
        guard !isBroken else { return }
        if let last = lastCommitted, !last.separator.isEmpty {
            // Стёрт разделитель — курсор снова в конце предыдущего слова.
            raw = Array(last.word)
            lastCommitted = nil
        } else {
            // Стирается текст, которого мы не видели: следующий набор — обрывок.
            lastCommitted = nil
            isBroken = true
        }
    }

    /// Сброс при потере контекста курсора (клик мыши, стрелки, Esc,
    /// Cmd-комбинации, смена приложения): забываем и последнее слово —
    /// иначе Double-Shift удалил бы символы в новом месте.
    public func reset() {
        raw = []
        isBroken = false
        lastCommitted = nil
    }

    /// Фиксация слова по разделителю. Возвращает чистый токен или nil,
    /// если буфер пуст/загрязнён. Буфер очищается в любом случае.
    /// - Parameter remember: false для Enter/Tab — после них слово нельзя
    ///   безопасно перенабрать (отправленное сообщение, другое поле).
    @discardableResult
    public func commit(separator: String, remember: Bool = true) -> String? {
        let word = current
        let clean = !raw.isEmpty && !isTainted
        raw = []
        isBroken = false
        lastCommitted = clean && remember ? (word, separator) : nil
        return clean ? word : nil
    }

    /// Обновить «последнее слово» после авто-исправления, чтобы Double-Shift
    /// мог откатить замену.
    public func setLastCommitted(word: String, separator: String) {
        lastCommitted = (word, separator)
    }

    /// Заменить текущее (ещё не закоммиченное) слово после ручной конвертации.
    public func replaceCurrent(with text: String) {
        raw = Array(text)
        isBroken = false
    }
}
