import AppKit
import Carbon
import Foundation

/// Чтение и переключение системных input sources через TIS API (FR-3).
///
/// ВАЖНО: TIS-функции обязаны вызываться на главном потоке (HIToolbox
/// ассертит `dispatch_assert_queue(main)`). Движок работает на фоновом потоке
/// event tap, поэтому:
/// - текущая раскладка кешируется и обновляется по системному уведомлению,
///   так что `current()` безопасен из любого потока;
/// - `select(_:)` маршалит реальную смену на главный поток.
public final class LayoutController {
    private var cache: [Layout: TISInputSource] = [:]
    private let lock = NSLock()
    private var cachedCurrent: Layout?

    public init() {
        refreshCurrentCache()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceChanged),
            name: NSNotification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
            object: nil
        )
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    /// Текущая раскладка из кеша; nil — неподдерживаемый язык. Потокобезопасно.
    public func current() -> Layout? {
        lock.lock()
        defer { lock.unlock() }
        return cachedCurrent
    }

    /// Переключение раскладки на уровне системы. Безопасно из любого потока:
    /// реальный вызов TIS выполняется на главном потоке.
    public func select(_ layout: Layout) {
        if Thread.isMainThread {
            performSelect(layout)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.performSelect(layout)
            }
        }
    }

    // MARK: - Private (главный поток)

    private func performSelect(_ layout: Layout) {
        // Реальную текущую раскладку читаем здесь, на главном потоке (TIS
        // безопасен), а не из кеша: кеш обновляется по distributed-уведомлению,
        // которое может потеряться, и тогда нужное переключение не произошло бы.
        if let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
           Self.layout(of: currentSource) == layout {
            setCachedCurrent(layout)
            return
        }
        guard let source = inputSource(for: layout) else {
            Log.engine.error("Input source для раскладки \(layout.rawValue) не найден")
            return
        }
        TISSelectInputSource(source)
        setCachedCurrent(layout)
    }

    private func setCachedCurrent(_ layout: Layout?) {
        lock.lock()
        cachedCurrent = layout
        lock.unlock()
    }

    @objc private func inputSourceChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshCurrentCache()
        }
    }

    /// Читает текущую раскладку из TIS (главный поток) и кладёт в кеш.
    private func refreshCurrentCache() {
        let layout: Layout?
        if let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() {
            layout = Self.layout(of: source)
        } else {
            layout = nil
        }
        setCachedCurrent(layout)
    }

    static func layout(of source: TISInputSource) -> Layout? {
        guard let languages: [String] = property(source, kTISPropertyInputSourceLanguages),
              let primary = languages.first else {
            return nil
        }
        if primary.hasPrefix("ru") { return .ru }
        if primary.hasPrefix("en") { return .en }
        return nil
    }

    private func inputSource(for layout: Layout) -> TISInputSource? {
        if let cached = cache[layout] { return cached }

        guard let cfList = TISCreateInputSourceList(nil, false)?.takeRetainedValue() else {
            return nil
        }
        let count = CFArrayGetCount(cfList)
        for index in 0..<count {
            let source = unsafeBitCast(
                CFArrayGetValueAtIndex(cfList, index),
                to: TISInputSource.self
            )
            guard let category: String = Self.property(source, kTISPropertyInputSourceCategory),
                  category == (kTISCategoryKeyboardInputSource as String),
                  let selectable: Bool = Self.property(source, kTISPropertyInputSourceIsSelectCapable),
                  selectable,
                  let enabled: Bool = Self.property(source, kTISPropertyInputSourceIsEnabled),
                  enabled,
                  Self.layout(of: source) == layout else {
                continue
            }
            cache[layout] = source
            return source
        }
        return nil
    }

    private static func property<T>(_ source: TISInputSource, _ key: CFString) -> T? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue() as? T
    }
}
