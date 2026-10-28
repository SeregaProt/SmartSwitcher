import AppKit

/// Механизм обновлений (раздел 14 ТЗ).
///
/// Полная интеграция Sparkle (appcast, EdDSA, дельты) выполняется в фазе
/// релиза — она требует хостинга appcast-фида и подписи Developer ID
/// (см. docs/adr/0006-updates.md). Сейчас сервис ведёт учёт канала и
/// авто-проверки и открывает страницу релизов; интерфейс стабилен, замена
/// внутренностей на Sparkle не затронет UI.
public final class UpdateService {
    public enum Channel: String, CaseIterable {
        case stable
        case beta
    }

    private let preferences: Preferences
    private let session: URLSession

    /// Базовый адрес фида/релизов. Канал добавляется как суффикс.
    public static let releasesURL = URL(string: "https://github.com/smartswitcher/smartswitcher/releases")!
    public static let appcastBase = "https://smartswitcher.app/appcast"

    public init(preferences: Preferences, session: URLSession = .shared) {
        self.preferences = preferences
        self.session = session
    }

    public var channel: Channel {
        Channel(rawValue: preferences.updateChannel) ?? .stable
    }

    public func setChannel(_ channel: Channel) {
        preferences.updateChannel = channel.rawValue
    }

    /// URL appcast для текущего канала (для будущей Sparkle-интеграции).
    public var appcastURL: URL? {
        URL(string: "\(Self.appcastBase)-\(channel.rawValue).xml")
    }

    /// Ручная проверка по действию пользователя.
    public func checkForUpdates() {
        NSWorkspace.shared.open(Self.releasesURL)
    }

    /// Фоновая проверка при старте (раздел 14): только если включена авто-проверка.
    /// До Sparkle — лёгкий best-effort запрос наличия фида, без UI-навязчивости.
    public func checkInBackgroundIfDue() {
        guard preferences.autoCheckUpdates, let url = appcastURL else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10
        session.dataTask(with: request) { _, response, _ in
            guard let http = response as? HTTPURLResponse else { return }
            if http.statusCode == 200 {
                Log.app.info("Канал обновлений \(self.channel.rawValue): фид доступен")
            }
        }.resume()
    }
}
