import AppKit
import CoreGraphics

/// Глобальный перехват клавиатуры через CGEventTap (FR-1).
/// Работает в режиме listen-only: события никогда не блокируются и не
/// модифицируются — приложение не может «съесть» ввод (NFR: надёжность).
/// Tap крутится на выделенном потоке с собственным run loop.
public final class EventTapManager {
    public enum TapEvent {
        case keyDown(keyCode: Int64, flags: CGEventFlags, characters: String)
        case flagsChanged(keyCode: Int64, flags: CGEventFlags, timestamp: TimeInterval)
        case mouseDown
    }

    /// Вызывается на потоке event tap. Обработчик обязан быть быстрым (< 5 мс).
    public var handler: ((TapEvent) -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var thread: Thread?

    public init() {}

    public var isRunning: Bool { tap != nil }

    /// Запуск перехвата. false — нет прав Accessibility или tap не создался.
    @discardableResult
    public func start() -> Bool {
        guard tap == nil else { return true }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<EventTapManager>.fromOpaque(userInfo).takeUnretainedValue()
            manager.process(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.engine.error("Не удалось создать event tap (нет прав Accessibility?)")
            return false
        }

        self.tap = tap
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

        Log.engine.info("Event tap запущен")
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
        Log.engine.info("Event tap остановлен")
    }

    private func process(type: CGEventType, event: CGEvent) {
        // Система отключает tap при таймауте — переподключаемся (раздел 12 ТЗ).
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            Log.engine.warning("Event tap был отключён системой, включаю заново")
            return
        }

        // Игнорируем собственные синтетические события перенабора.
        if event.getIntegerValueField(.eventSourceUserData) == TextReplacer.injectionMarker {
            return
        }

        switch type {
        case .keyDown:
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
    }
}
