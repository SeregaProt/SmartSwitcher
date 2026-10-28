import CoreGraphics
import Foundation

/// Обнаружение конкурирующих перехватчиков клавиатуры (раздел 21 ТЗ):
/// Karabiner, Keyboard Maestro, другие свитчеры. При конфликте приложение
/// продолжает работать, но предупреждает пользователя.
public final class ConflictDetector: Sendable {
    public init() {}

    /// Количество чужих активных event tap'ов, слушающих клавиатуру.
    public func competingKeyboardTaps() -> Int {
        var count: UInt32 = 0
        guard CGGetEventTapList(0, nil, &count) == .success, count > 0 else { return 0 }
        var taps = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(count))
        guard CGGetEventTapList(count, &taps, &count) == .success else { return 0 }

        let keyboardMask: UInt64 =
            (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let ownPID = ProcessInfo.processInfo.processIdentifier

        return taps.filter { tap in
            tap.tappingProcess != ownPID
                && tap.enabled
                && (tap.eventsOfInterest & keyboardMask) != 0
                // Активные (не listen-only) тапы могут менять события — главный риск.
                && tap.options == .defaultTap
        }.count
    }
}
