import CoreGraphics
import Foundation

/// Распознанный жест клавишей Shift.
public enum ShiftGesture: Equatable, Sendable {
    case none
    /// Одиночное нажатие Shift без других клавиш (FR-4, Single-Shift).
    case single
    /// Два одиночных нажатия Shift подряд в окне (FR-4, Double-Shift).
    case double
}

/// Распознавание жестов Shift (FR-4): одиночное и двойное нажатие без других
/// клавиш и модификаторов между ними. Чистая логика без системных зависимостей —
/// покрыта unit-тестами.
///
/// Окно `window` задаёт максимальный интервал между двумя нажатиями для double.
/// Single эмитится по таймеру после одиночного нажатия, если за `window` не
/// пришло второе (чтобы не конфликтовать с double) — это делает вызывающая
/// сторона, опрашивая `pendingSingle(now:)`.
public final class ShiftGestureDetector {
    public static let leftShiftKeyCode: Int64 = 56
    public static let rightShiftKeyCode: Int64 = 60

    private var window: TimeInterval
    private var lastShiftUpTime: TimeInterval?
    private var shiftIsDownAlone = false

    public init(window: TimeInterval = 0.4) {
        self.window = window
    }

    public func setWindow(_ value: TimeInterval) {
        window = value
    }

    /// Любая обычная клавиша между нажатиями Shift сбрасывает жест
    /// (в том числе ввод заглавных букв с зажатым Shift).
    public func noteKeyDown() {
        lastShiftUpTime = nil
        shiftIsDownAlone = false
    }

    /// Обработка flagsChanged. Возвращает распознанный жест.
    /// `.double` — сразу при втором быстром нажатии.
    /// `.single` — здесь НЕ возвращается напрямую (нужно подождать окно);
    /// вызывающая сторона должна опросить `pendingSingle(now:)` по таймеру.
    public func handleFlagsChanged(keyCode: Int64, flags: CGEventFlags, time: TimeInterval) -> ShiftGesture {
        let isShiftKey = keyCode == Self.leftShiftKeyCode || keyCode == Self.rightShiftKeyCode
        guard isShiftKey else {
            lastShiftUpTime = nil
            shiftIsDownAlone = false
            return .none
        }

        let otherModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskSecondaryFn]
        guard flags.intersection(otherModifiers).isEmpty else {
            lastShiftUpTime = nil
            shiftIsDownAlone = false
            return .none
        }

        if flags.contains(.maskShift) {
            shiftIsDownAlone = true
            return .none
        }

        // Shift отпущен.
        guard shiftIsDownAlone else { return .none }
        shiftIsDownAlone = false

        if let last = lastShiftUpTime, time - last <= window {
            lastShiftUpTime = nil
            return .double
        }
        lastShiftUpTime = time
        return .none
    }

    /// Возвращает `.single`, если после одиночного нажатия прошло больше окна
    /// и второго нажатия не последовало. Вызывается по таймеру.
    public func pendingSingle(now: TimeInterval) -> ShiftGesture {
        guard let last = lastShiftUpTime, now - last > window else { return .none }
        lastShiftUpTime = nil
        return .single
    }
}

/// Совместимость с прежним API (тесты фазы 1). Тонкая обёртка над
/// ShiftGestureDetector, эмитит только double.
public final class DoubleShiftDetector {
    public static let leftShiftKeyCode = ShiftGestureDetector.leftShiftKeyCode
    public static let rightShiftKeyCode = ShiftGestureDetector.rightShiftKeyCode

    private let detector: ShiftGestureDetector

    public init(window: TimeInterval = 0.4) {
        detector = ShiftGestureDetector(window: window)
    }

    public func noteKeyDown() { detector.noteKeyDown() }

    public func handleFlagsChanged(keyCode: Int64, flags: CGEventFlags, time: TimeInterval) -> Bool {
        detector.handleFlagsChanged(keyCode: keyCode, flags: flags, time: time) == .double
    }
}
