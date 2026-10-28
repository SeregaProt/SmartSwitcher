import CoreGraphics
import Foundation

/// Удаление неверно набранного слова и вставка исправленного (FR-3).
///
/// Удаление — эмуляция Backspace; вставка — синтетические key-события
/// с явной unicode-строкой (`keyboardSetUnicodeString`), поэтому результат
/// не зависит от активной раскладки и от порядка её переключения.
/// Каждый символ (графема) — отдельное событие: часть приложений (Electron,
/// Java, игры) берёт из события только первый символ, а суррогатные пары
/// и составные эмодзи не должны разрываться.
/// Все события помечаются маркером, чтобы собственный event tap их игнорировал.
public final class TextReplacer {
    /// "SMSW" — метка собственных синтетических событий.
    public static let injectionMarker: Int64 = 0x534D_5357

    private enum KeyCode {
        static let backspace: CGKeyCode = 51
        static let returnKey: CGKeyCode = 36
    }

    private let source: CGEventSource?
    /// Пауза между событиями, мкс — даёт приложениям успеть обработать ввод.
    /// Чем короче перенабор, тем меньше окно гонки с быстрым набором
    /// в listen-only режиме.
    private let interEventDelay: UInt32 = 500

    /// Придерживание пользовательского ввода (надёжный режим).
    public var gate: InputGate?

    public init() {
        source = CGEventSource(stateID: .hidSystemState)
    }

    /// Удаляет `deleteCount` символов перед курсором и набирает `text`.
    public func replace(deleteCount: Int, with text: String) {
        holdingInput {
            for _ in 0..<deleteCount {
                postKey(KeyCode.backspace)
            }
            type(text)
        }
    }

    /// Выполнить серию синтетических событий, придержав ввод пользователя.
    public func holdingInput(_ body: () -> Void) {
        gate?.hold()
        defer { gate?.release() }
        body()
    }

    public func type(_ text: String) {
        for character in text {
            let units = Array(String(character).utf16)
            for keyDown in [true, false] {
                guard let event = CGEvent(
                    keyboardEventSource: source,
                    virtualKey: 0,
                    keyDown: keyDown
                ) else { continue }
                event.flags = []
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                event.setIntegerValueField(.eventSourceUserData, value: Self.injectionMarker)
                event.post(tap: .cghidEventTap)
            }
            usleep(interEventDelay)
        }
    }

    /// Повторная отправка Enter, придержанного до исправления слова (ADR-0008).
    public func postReturn(flags: CGEventFlags) {
        postKey(KeyCode.returnKey, flags: flags)
    }

    private func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
        for keyDown in [true, false] {
            guard let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: keyCode,
                keyDown: keyDown
            ) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: Self.injectionMarker)
            event.post(tap: .cghidEventTap)
        }
        usleep(interEventDelay)
    }
}
