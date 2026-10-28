import CoreGraphics
import Foundation

/// Придерживание ввода на время перенабора (надёжный режим, ADR-0008).
///
/// Пока `TextReplacer` удаляет и впечатывает слово, активный event tap
/// забирает нажатия пользователя сюда, а после замены воспроизводит их
/// в исходном порядке — быстрый набор не смешивается с перенабором.
/// Предохранитель: удержание не дольше `maxHold`, даже если движок завис.
public final class InputGate {
    public static let maxHold: TimeInterval = 0.5

    private let lock = NSLock()
    private var depth = 0
    private var deadline: TimeInterval = 0
    private var held: [CGEvent] = []
    private let replay: ([CGEvent]) -> Void

    /// Включается только при активном tap (в listen-only событие не поглотить).
    public var isEnabled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return enabled }
        set { lock.lock(); enabled = newValue; lock.unlock() }
    }

    private var enabled = false

    /// - Parameter replay: как воспроизвести придержанные события (тесты подменяют).
    public init(replay: @escaping ([CGEvent]) -> Void = InputGate.post) {
        self.replay = replay
    }

    /// Начать удержание (вложенные вызовы считаются).
    public func hold() {
        lock.lock()
        defer { lock.unlock() }
        guard enabled else { return }
        depth += 1
        deadline = ProcessInfo.processInfo.systemUptime + Self.maxHold
    }

    /// Закончить удержание; на последнем уровне — воспроизвести придержанное.
    public func release() {
        lock.lock()
        guard depth > 0 else { lock.unlock(); return }
        depth -= 1
        let events = depth == 0 ? drain() : []
        lock.unlock()
        if !events.isEmpty { replay(events) }
    }

    /// Поток event tap: true — событие придержано (вернуть nil из tap).
    public func capture(_ event: CGEvent) -> Bool {
        lock.lock()
        guard depth > 0 else { lock.unlock(); return false }
        if ProcessInfo.processInfo.systemUptime > deadline {
            // Предохранитель: движок не отпустил ввод вовремя.
            depth = 0
            let events = drain()
            lock.unlock()
            replay(events)
            Log.engine.warning("InputGate: удержание прервано по таймауту")
            return false
        }
        guard let copy = event.copy() else { lock.unlock(); return false }
        held.append(copy)
        lock.unlock()
        return true
    }

    /// Вызывается под `lock`.
    private func drain() -> [CGEvent] {
        let events = held
        held = []
        return events
    }

    /// Повторная отправка с меткой: tap пропустит их, движок уже видел оригиналы.
    public static func post(_ events: [CGEvent]) {
        for event in events {
            event.setIntegerValueField(.eventSourceUserData, value: TextReplacer.injectionMarker)
            event.post(tap: .cghidEventTap)
        }
    }
}
