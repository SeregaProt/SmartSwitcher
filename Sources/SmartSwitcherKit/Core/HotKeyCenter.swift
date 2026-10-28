import Carbon

/// Глобальные горячие клавиши через Carbon `RegisterEventHotKey`: не требует
/// дополнительных прав и не видит остальной ввод. Срабатывание — по отпусканию
/// клавиши, обработчики вызываются на главном потоке.
public final class HotKeyCenter {
    public struct Shortcut: Equatable {
        public let keyCode: UInt32
        public let modifiers: UInt32

        public init(keyCode: UInt32, modifiers: UInt32) {
            self.keyCode = keyCode
            self.modifiers = modifiers
        }

        /// ⌃⌥ + клавиша (виртуальный код ANSI, не зависит от раскладки).
        public static func controlOption(_ keyCode: UInt32) -> Shortcut {
            Shortcut(keyCode: keyCode, modifiers: UInt32(controlKey | optionKey))
        }
    }

    private static let signature: OSType = 0x534D_5357 // "SMSW"

    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1
    private var handlerRef: EventHandlerRef?

    public init() {}

    deinit {
        unregisterAll()
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    @discardableResult
    public func register(_ shortcut: Shortcut, action: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            Log.app.warning("Хоткей не зарегистрирован (занят?): код \(shortcut.keyCode)")
            return false
        }
        refs.append(ref)
        actions[id] = action
        return true
    }

    public func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        actions = [:]
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            center.actions[hotKeyID.id]?()
            return noErr
        }
        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
    }
}
