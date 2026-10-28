/// Поддерживаемая раскладка клавиатуры.
/// Архитектурно подсистема детекта расширяема: новые языки добавляются
/// новой парой (Layout, маппинг, словари) без изменения ядра.
public enum Layout: String, CaseIterable, Equatable, Sendable {
    case en
    case ru

    public var other: Layout {
        self == .en ? .ru : .en
    }

    /// Текст для иконки в menu bar.
    public var displayName: String {
        rawValue.uppercased()
    }
}
