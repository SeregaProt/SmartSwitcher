import AppKit

/// Ненавязчивый индикатор у текстового курсора при исправлении (FR-8):
/// короткая плашка «RU»/«EN», которая гаснет сама. Не забирает фокус
/// и не перехватывает мышь. Позиция каретки — через Accessibility,
/// если приложение её не отдаёт — рядом с указателем мыши.
@MainActor
public final class CorrectionHUD {
    private static let messagingTimeout: Float = 0.1

    private var panel: NSPanel?
    private let label = NSTextField(labelWithString: "")
    private var hideWorkItem: DispatchWorkItem?

    public init() {}

    /// Показать плашку (главный поток).
    public func show(_ text: String) {
        let panel = panel ?? makePanel()
        self.panel = panel
        label.stringValue = text
        label.sizeToFit()
        let size = NSSize(width: max(36, label.frame.width + 16), height: 24)
        let anchor = Self.caretRect() ?? NSRect(origin: NSEvent.mouseLocation, size: .zero)
        let origin = NSPoint(x: anchor.minX, y: anchor.minY - size.height - 4)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        label.frame = NSRect(x: 0, y: (size.height - label.frame.height) / 2, width: size.width, height: label.frame.height)

        hideWorkItem?.cancel()
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        let work = DispatchWorkItem { [weak panel] in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                panel?.animator().alphaValue = 0
            } completionHandler: {
                MainActor.assumeIsolated { panel?.orderOut(nil) }
            }
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 40, height: 24),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]

        let background = NSVisualEffectView(frame: panel.contentLayoutRect)
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 6
        background.autoresizingMask = [.width, .height]

        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.alignment = .center
        label.textColor = .labelColor
        background.addSubview(label)
        panel.contentView = background
        return panel
    }

    /// Прямоугольник каретки в координатах Cocoa (начало — внизу слева).
    private static func caretRect() -> NSRect? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, messagingTimeout)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeDowncast(focusedRef as AnyObject, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef else { return nil }
        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeRef,
            &boundsRef
        ) == .success, let boundsRef, CFGetTypeID(boundsRef) == AXValueGetTypeID() else { return nil }

        var rect = CGRect.zero
        // swiftlint:disable:next force_cast
        guard AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect), rect.width >= 0, rect.height > 0 else {
            return nil
        }
        // AX: начало координат вверху слева главного экрана.
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
        return NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
