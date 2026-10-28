import Foundation
import UserNotifications

/// Ненавязчивые уведомления о срабатывании (FR-8). По умолчанию выключены;
/// при включении запрашивается разрешение. Текст уведомления не содержит
/// исправленного слова (приватность, раздел 11) — только факт.
public final class NotificationService {
    private let preferences: Preferences
    private var authorized = false

    public init(preferences: Preferences) {
        self.preferences = preferences
    }

    /// Запрос разрешения (вызывается при включении тумблера в настройках).
    public func requestAuthorizationIfNeeded() {
        guard preferences.notificationsEnabled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { [weak self] granted, _ in
            self?.authorized = granted
        }
    }

    public func notifyCorrection(to layout: Layout) {
        guard preferences.notificationsEnabled else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = "SmartSwitcher"
            content.body = String(
                format: L10n.text("notify.switched", "Раскладка переключена на %@"),
                layout.displayName
            )
            content.interruptionLevel = .passive
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }
}
