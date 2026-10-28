import AppKit
import ApplicationServices

/// Проверка и запрос прав Accessibility (онбординг, раздел 4.4 ТЗ).
public enum PermissionsManager {
    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Показывает системный диалог запроса прав.
    public static func requestWithPrompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
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

/// Определение фокуса в secure text field (поле пароля) через Accessibility API (FR-5).
public final class FocusInspector {
    public init() {}

    public func isSecureFieldFocused() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
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

        var subroleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef)
        if let subrole = subroleRef as? String, subrole == "AXSecureTextField" {
            return true
        }
        return false
    }
}
