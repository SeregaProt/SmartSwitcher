import Foundation

/// Экспорт/импорт настроек и правил в человекочитаемый JSON (раздел 24 ТЗ).
/// Синхронизируются только настройки — никогда набранный текст (раздел 15).
public final class ImportExportService {
    public struct Snapshot: Codable, Equatable {
        public var version: Int
        public var enabled: Bool
        public var soundEnabled: Bool
        public var excludedApps: [String]
        public var neverCorrectWords: [String]
        public var alwaysCorrectWords: [String]
        // v2: хоткеи, автозамена, языки (опциональные для совместимости с v1).
        public var expansionRules: [String: String]?
        public var detectionLanguages: [String]?
        public var doubleShiftFixEnabled: Bool?
        public var singleShiftSwitchEnabled: Bool?

        public static let currentVersion = 2
    }

    public enum ImportError: LocalizedError {
        case invalidFormat
        case unsupportedVersion(Int)

        public var errorDescription: String? {
            switch self {
            case .invalidFormat:
                return L10n.text("import.error.format", "Файл не является конфигурацией SmartSwitcher.")
            case let .unsupportedVersion(v):
                return L10n.text("import.error.version", "Неподдерживаемая версия конфигурации: \(v).")
            }
        }
    }

    private let preferences: Preferences

    public init(preferences: Preferences) {
        self.preferences = preferences
    }

    public func exportData() throws -> Data {
        let snapshot = Snapshot(
            version: Snapshot.currentVersion,
            enabled: preferences.enabled,
            soundEnabled: preferences.soundEnabled,
            excludedApps: preferences.excludedApps,
            neverCorrectWords: preferences.neverCorrectWords,
            alwaysCorrectWords: preferences.alwaysCorrectWords,
            expansionRules: preferences.expansionRules,
            detectionLanguages: preferences.detectionLanguages,
            doubleShiftFixEnabled: preferences.doubleShiftFixEnabled,
            singleShiftSwitchEnabled: preferences.singleShiftSwitchEnabled
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(snapshot)
    }

    /// Валидация и применение импортируемых данных (защита от некорректных файлов).
    public func importData(_ data: Data) throws {
        let snapshot: Snapshot
        do {
            snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        } catch {
            throw ImportError.invalidFormat
        }
        guard snapshot.version <= Snapshot.currentVersion, snapshot.version >= 1 else {
            throw ImportError.unsupportedVersion(snapshot.version)
        }
        let sanitize: ([String]) -> [String] = { list in
            Array(list.prefix(5000)).map { String($0.prefix(64)) }.filter { !$0.isEmpty }
        }
        DispatchQueue.main.async { [preferences] in
            preferences.enabled = snapshot.enabled
            preferences.soundEnabled = snapshot.soundEnabled
            preferences.excludedApps = sanitize(snapshot.excludedApps)
            preferences.neverCorrectWords = sanitize(snapshot.neverCorrectWords)
            preferences.alwaysCorrectWords = sanitize(snapshot.alwaysCorrectWords)
            if let rules = snapshot.expansionRules {
                let limited = rules.prefix(2000)
                preferences.expansionRules = Dictionary(
                    uniqueKeysWithValues: limited.map { (String($0.key.prefix(64)), String($0.value.prefix(256))) }
                )
            }
            if let langs = snapshot.detectionLanguages {
                let valid = langs.filter { Layout(rawValue: $0) != nil }
                if !valid.isEmpty { preferences.detectionLanguages = valid }
            }
            if let v = snapshot.doubleShiftFixEnabled { preferences.doubleShiftFixEnabled = v }
            if let v = snapshot.singleShiftSwitchEnabled { preferences.singleShiftSwitchEnabled = v }
        }
    }
}
