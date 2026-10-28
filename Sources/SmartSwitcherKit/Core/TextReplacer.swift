import CoreGraphics
import Foundation

/// Удаление неверно набранного слова и вставка исправленного (FR-3).
///
/// Удаление — эмуляция Backspace; вставка — синтетические key-события
/// с явной unicode-строкой (`keyboardSetUnicodeString`), поэтому результат
/// не зависит от активной раскладки и от порядка её переключения.
/// Все события помечаются маркером, чтобы собственный event tap их игнорировал.
public final class TextReplacer {
    /// "SMSW" — метка собственных синтетических событий.
    public static let injectionMarker: Int64 = 0x534D_5357

    private let source: CGEventSource?
    /// Пауза между событиями, мкс — даёт приложениям успеть обработать ввод.
    private let interEventDelay: UInt32 = 1200
    /// Максимум UTF-16 юнитов на одно событие (ограничение CGEvent).
    private let chunkSize = 16

    public init() {
        source = CGEventSource(stateID: .hidSystemState)
    }

    /// Удаляет `deleteCount` символов перед курсором и набирает `text`.
    public func replace(deleteCount: Int, with text: String) {
        for _ in 0..<deleteCount {
            postKey(51) // Backspace
        }
        type(text)
    }

    public func type(_ text: String) {
        let units = Array(text.utf16)
        var index = 0
        while index < units.count {
            let chunk = Array(units[index..<min(index + chunkSize, units.count)])
            for keyDown in [true, false] {
                guard let event = CGEvent(
                    keyboardEventSource: source,
                    virtualKey: 0,
                    keyDown: keyDown
                ) else { continue }
                event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                event.setIntegerValueField(.eventSourceUserData, value: Self.injectionMarker)
                event.post(tap: .cghidEventTap)
            }
            usleep(interEventDelay)
            index += chunkSize
        }
    }

    private func postKey(_ keyCode: CGKeyCode) {
        for keyDown in [true, false] {
            guard let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: keyCode,
                keyDown: keyDown
            ) else { continue }
            event.setIntegerValueField(.eventSourceUserData, value: Self.injectionMarker)
            event.post(tap: .cghidEventTap)
        }
        usleep(interEventDelay)
    }
}
