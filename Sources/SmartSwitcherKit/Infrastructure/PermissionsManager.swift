import AppKit
import ApplicationServices
import Carbon

/// Проверка и запрос прав Accessibility (онбординг, раздел 4.4 ТЗ).
public enum PermissionsManager {
    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Показывает системный диалог запроса прав.
    public static func requestWithPrompt() {
        // Значение kAXTrustedCheckOptionPrompt; глобальная var из C-заголовка
        // не concurrency-safe в Swift 6.
        let options = ["AXTrustedCheckOptionPrompt": true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Открывает панель Privacy & Security → Accessibility в Настройках.
    public static func openSystemSettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )!
        NSWorkspace.shared.open(url)
    }
}

/// Определение ввода пароля (FR-5): системный Secure Event Input (его
/// включают поля паролей, sudo в терминале, менеджеры паролей) и фокус
/// в AXSecureTextField.
public final class FocusInspector {
    /// Таймаут Accessibility-запросов: зависшее приложение не должно
    /// останавливать движок (по умолчанию система ждёт до 6 секунд).
    private static let messagingTimeout: Float = 0.15

    private let systemWide: AXUIElement

    public init() {
        systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, Self.messagingTimeout)
    }

    public func isSecureInputActive() -> Bool {
        if IsSecureEventInputEnabled() { return true }

        var focusedRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        guard result == .success,
              let focusedRef,
              CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            return false
        }
        let element = unsafeDowncast(focusedRef as AnyObject, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)

        var subroleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef)
        return (subroleRef as? String) == "AXSecureTextField"
    }
}
