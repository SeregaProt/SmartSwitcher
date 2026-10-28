import AppKit

/// Механизм обновлений (раздел 14 ТЗ).
///
/// Проверка версии — через GitHub Releases API репозитория проекта
/// (`SSGitHubRepository` в Info.plist). Без настроенного репозитория
/// проверка выключена: никаких запросов на чужие адреса. Установка —
/// пока через страницу релиза; Sparkle (appcast, EdDSA, дельты) подключается
/// с Developer ID (docs/adr/0006-updates-deferred-sparkle.md), интерфейс
/// сервиса при этом не меняется.
@MainActor
public final class UpdateService {
    public enum Channel: String, CaseIterable {
        case stable
        case beta
    }

    public enum CheckResult: Equatable {
        case upToDate
        case available(version: String, url: URL)
        case failed
    }

    private static let lastCheckKey = "updates.lastCheck"
    private static let checkInterval: TimeInterval = 24 * 3600

    private let preferences: Preferences
    private let session: URLSession
    private let bundle: Bundle

    /// Найдена новая версия (главный поток).
    public var onUpdateAvailable: ((String, URL) -> Void)?

    public init(preferences: Preferences, session: URLSession = .shared, bundle: Bundle = .main) {
        self.preferences = preferences
        self.session = session
        self.bundle = bundle
    }

    /// "owner/repo" из Info.plist; nil — обновления не настроены.
    public var repository: String? {
        guard let value = bundle.object(forInfoDictionaryKey: "SSGitHubRepository") as? String,
              value.split(separator: "/").count == 2 else { return nil }
        return value
    }

    public var isConfigured: Bool { repository != nil }

    public var currentVersion: String {
        bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    public var releasesPageURL: URL? {
        repository.flatMap { URL(string: "https://github.com/\($0)/releases") }
    }

    public var channel: Channel {
        Channel(rawValue: preferences.updateChannel) ?? .stable
    }

    public func setChannel(_ channel: Channel) {
        preferences.updateChannel = channel.rawValue
    }

    /// Ручная проверка по действию пользователя; результат — на главном потоке.
    public func check(completion: @escaping @MainActor (CheckResult) -> Void) {
        guard let repository,
              let url = URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=10") else {
            completion(.failed)
            return
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        let includeBeta = channel == .beta
        let current = currentVersion
        session.dataTask(with: request) { data, response, _ in
            let result: CheckResult
            if let data,
               (response as? HTTPURLResponse)?.statusCode == 200,
               let releases = try? JSONDecoder().decode([Release].self, from: data) {
                result = Self.evaluate(releases, current: current, includeBeta: includeBeta)
            } else {
                result = .failed
            }
            DispatchQueue.main.async {
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
                completion(result)
            }
        }.resume()
    }

    /// Фоновая проверка (раздел 14): не чаще раза в сутки, только если включена.
    public func checkInBackgroundIfDue() {
        guard preferences.autoCheckUpdates, isConfigured else { return }
        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        guard Date().timeIntervalSince1970 - last > Self.checkInterval else { return }
        check { [weak self] result in
            if case let .available(version, url) = result {
                Log.app.info("Доступно обновление \(version)")
                self?.onUpdateAvailable?(version, url)
            }
        }
    }

    // MARK: - Сравнение версий

    struct Release: Decodable, Sendable {
        let tag_name: String
        let html_url: URL
        let prerelease: Bool
        let draft: Bool
    }

    nonisolated static func evaluate(_ releases: [Release], current: String, includeBeta: Bool) -> CheckResult {
        let candidates = releases.filter { !$0.draft && (includeBeta || !$0.prerelease) }
        guard let newest = candidates.max(by: { isNewer($1.tag_name, than: $0.tag_name) }) else {
            return .upToDate
        }
        let version = normalized(newest.tag_name)
        return isNewer(version, than: current)
            ? .available(version: version, url: newest.html_url)
            : .upToDate
    }

    /// Семантическое сравнение "1.10.0" > "1.9.2"; префикс "v" игнорируется.
    public nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = components(candidate), b = components(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private nonisolated static func normalized(_ tag: String) -> String {
        tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
    }

    private nonisolated static func components(_ version: String) -> [Int] {
        normalized(version)
            .split(whereSeparator: { $0 == "." || $0 == "-" })
            .map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }
}
