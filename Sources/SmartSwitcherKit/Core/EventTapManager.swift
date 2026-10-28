import AppKit
import CoreGraphics

/// Глобальный перехват клавиатуры через CGEventTap (FR-1).
///
/// По умолчанию — listen-only: события никогда не блокируются и не
/// модифицируются, приложение не может «съесть» ввод (ADR-0001).
/// Надёжный режим (ADR-0008) включает активный tap: на время перенабора
/// нажатия придерживаются в `InputGate`, а Enter — пока исправляется слово.
/// Tap крутится на выделенном потоке с собственным run loop.
///
/// `@unchecked Sendable`: tap и run loop создаются/останавливаются на главном
/// потоке, поток tap только читает их; обработчики задаются один раз при старте.
public final class EventTapManager: @unchecked Sendable {
    public enum TapEvent: Sendable {
        case keyDown(keyCode: Int64, flags: CGEventFlags, characters: String)
        case flagsChanged(keyCode: Int64, flags: CGEventFlags, timestamp: TimeInterval)
        case mouseDown
        /// Часть событий могла быть пропущена (tap отключался) или фокус ушёл
        /// в другое приложение — состояние набора больше не достоверно.
        case contextLost
    }

    private enum KeyCode {
        static let returnKey: Int64 = 36
        static let keypadEnter: Int64 = 76
    }

    /// Вызывается на потоке event tap. Обработчик обязан быть быстрым (< 5 мс).
    public var handler: ((TapEvent) -> Void)?

    /// Только для активного tap: true — Enter придержан, обработчик сам
    /// повторит его после исправления. Вызывается на потоке event tap.
    public var enterInterceptor: ((CGEventFlags) -> Bool)?

    /// Придерживание ввода во время перенабора (активен только с активным tap).
    public let gate: InputGate

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    public private(set) var interceptsEnter = false

    public init(gate: InputGate = InputGate()) {
        self.gate = gate
    }

    public var isRunning: Bool { tap != nil }

    /// Запуск перехвата. false — нет прав Accessibility или tap не создался.
    @discardableResult
    public func start(interceptEnter: Bool = false) -> Bool {
        guard tap == nil else { return true }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<EventTapManager>.fromOpaque(userInfo).takeUnretainedValue()
            return manager.process(type: type, event: event)
                ? Unmanaged.passUnretained(event)
                : nil
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: interceptEnter ? .defaultTap : .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.engine.error("Не удалось создать event tap (нет прав Accessibility?)")
            return false
        }

        self.tap = tap
        interceptsEnter = interceptEnter
        gate.isEnabled = interceptEnter
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source

        let thread = Thread { [weak self] in
            guard let self, let source = self.runLoopSource, let tap = self.tap else { return }
            self.runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "SmartSwitcher.EventTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        self.thread = thread

        Log.engine.info("Event tap запущен (\(interceptEnter ? "активный, Enter" : "listen-only"))")
        return true
    }

    public func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let runLoop { CFRunLoopStop(runLoop) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        self.runLoopSource = nil
        self.runLoop = nil
        self.thread = nil
        interceptsEnter = false
        gate.isEnabled = false
        Log.engine.info("Event tap остановлен")
    }

    /// Перезапуск с другим режимом (переключение опции в настройках).
    public func restart(interceptEnter: Bool) {
        guard isRunning, interceptEnter != interceptsEnter else { return }
        stop()
        start(interceptEnter: interceptEnter)
    }

    /// Возвращает false, если событие нужно поглотить.
    private func process(type: CGEventType, event: CGEvent) -> Bool {
        // Система отключает tap при таймауте — переподключаемся (раздел 12 ТЗ);
        // пропущенные нажатия делают буфер недостоверным.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            Log.engine.warning("Event tap был отключён системой, включаю заново")
            handler?(.contextLost)
            return true
        }

        // Игнорируем собственные синтетические события перенабора.
        if event.getIntegerValueField(.eventSourceUserData) == TextReplacer.injectionMarker {
            return true
        }

        // Надёжный режим: пока идёт перенабор, нажатия пользователя ждут.
        // Движок получает keyDown сразу (порядок в его очереди сохраняется),
        // а в приложение событие уйдёт повтором после замены.
        if (type == .keyDown || type == .keyUp), gate.capture(event) {
            if type == .keyDown { forwardKeyDown(event) }
            return false
        }

        switch type {
        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if interceptsEnter,
               keyCode == KeyCode.returnKey || keyCode == KeyCode.keypadEnter,
               event.flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty,
               enterInterceptor?(event.flags) == true {
                return false
            }
            forwardKeyDown(event)

        case .flagsChanged:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            handler?(.flagsChanged(
                keyCode: keyCode,
                flags: event.flags,
                timestamp: Double(event.timestamp) / 1_000_000_000.0
            ))

        case .leftMouseDown, .rightMouseDown:
            handler?(.mouseDown)

        default:
            break
        }
        return true
    }

    private func forwardKeyDown(_ event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(
            maxStringLength: 4,
            actualStringLength: &length,
            unicodeString: &buffer
        )
        let characters = String(utf16CodeUnits: buffer, count: length)
        handler?(.keyDown(keyCode: keyCode, flags: event.flags, characters: characters))
    }
}
