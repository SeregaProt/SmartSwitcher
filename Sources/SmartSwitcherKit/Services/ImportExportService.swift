import Foundation

/// Экспорт/импорт настроек и правил в человекочитаемый JSON (раздел 24 ТЗ).
/// Синхронизируются только настройки — никогда набранный текст (раздел 15).
///
/// `Sendable`: неизменяемая ссылка на потокобезопасные `Preferences`;
/// применение импорта всегда выполняется на главном потоке.
public final class ImportExportService: Sendable {
    public struct Snapshot: Codable, Equatable, Sendable {
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
        // v3: режимы приложений и метки правил слов для слияния.
        public var manualOnlyApps: [String]?
        public var wordRuleAdded: [String: Double]?
        public var wordRuleRemoved: [String: Double]?

        public static let currentVersion = 3
    }

    /// Как применять импорт.
    public enum Mode: Sendable {
        /// Файл от пользователя: заменить всё, включая «включено».
        case replace
        /// Синхронизация: списки слов сливаются по меткам времени,
        /// флаг «включено» остаётся локальным для каждого Mac.
        case merge
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
            singleShiftSwitchEnabled: preferences.singleShiftSwitchEnabled,
            manualOnlyApps: preferences.manualOnlyApps,
            wordRuleAdded: preferences.wordRuleAdded,
            wordRuleRemoved: preferences.wordRuleRemoved
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(snapshot)
    }

    /// Валидация и применение импортируемых данных (защита от некорректных файлов).
    public func importData(_ data: Data, mode: Mode = .replace) throws {
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
        let apply: @MainActor () -> Void = { [preferences] in
            if mode == .replace { preferences.enabled = snapshot.enabled }
            preferences.soundEnabled = snapshot.soundEnabled
            preferences.excludedApps = sanitize(snapshot.excludedApps)
            if let apps = snapshot.manualOnlyApps { preferences.manualOnlyApps = sanitize(apps) }

            let never = sanitize(snapshot.neverCorrectWords)
            let always = sanitize(snapshot.alwaysCorrectWords)
            switch mode {
            case .replace:
                preferences.neverCorrectWords = never
                preferences.alwaysCorrectWords = always
            case .merge:
                let merged = WordRuleMerge.merge(
                    local: WordRuleMerge.State(
                        never: preferences.neverCorrectWords,
                        always: preferences.alwaysCorrectWords,
                        added: preferences.wordRuleAdded,
                        removed: preferences.wordRuleRemoved
                    ),
                    remote: WordRuleMerge.State(
                        never: never,
                        always: always,
                        added: snapshot.wordRuleAdded ?? [:],
                        removed: snapshot.wordRuleRemoved ?? [:]
                    )
                )
                preferences.applyMergedWordRules(
                    never: merged.never,
                    always: merged.always,
                    added: merged.added,
                    removed: merged.removed
                )
            }

            if let rules = snapshot.expansionRules {
                let limited = rules.prefix(2000)
                preferences.expansionRules = Dictionary(
                    limited.map { (String($0.key.prefix(64)), String($0.value.prefix(256))) },
                    uniquingKeysWith: { first, _ in first }
                )
            }
            if let langs = snapshot.detectionLanguages {
                let valid = langs.filter { Layout(rawValue: $0) != nil }
                if !valid.isEmpty { preferences.detectionLanguages = valid }
            }
            if let v = snapshot.doubleShiftFixEnabled { preferences.doubleShiftFixEnabled = v }
            if let v = snapshot.singleShiftSwitchEnabled { preferences.singleShiftSwitchEnabled = v }
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated(apply)
        } else {
            DispatchQueue.main.async { apply() }
        }
    }
}

/// Слияние правил слов двух устройств (LWW-element-set): слово присутствует,
/// если его последнее добавление новее последнего удаления. Слова без меток
/// (до v3) считаются добавленными в момент 0 — любое удаление их перекрывает.
public enum WordRuleMerge {
    public struct State: Equatable {
        public var never: [String]
        public var always: [String]
        public var added: [String: Double]
        public var removed: [String: Double]

        public init(never: [String], always: [String], added: [String: Double], removed: [String: Double]) {
            self.never = never
            self.always = always
            self.added = added
            self.removed = removed
        }
    }

    public static func merge(local: State, remote: State) -> State {
        let added = local.added.merging(remote.added, uniquingKeysWith: max)
        let removed = local.removed.merging(remote.removed, uniquingKeysWith: max)

        func mergeList(_ kind: String, _ localList: [String], _ remoteList: [String]) -> [String] {
            let present = Set(localList).union(remoteList)
            var candidates = localList
            for word in remoteList where !candidates.contains(word) { candidates.append(word) }
            let prefix = kind + ":"
            for key in added.keys.sorted() where key.hasPrefix(prefix) {
                let word = String(key.dropFirst(prefix.count))
                if !candidates.contains(word) { candidates.append(word) }
            }
            return candidates.filter { word in
                let key = prefix + word
                let addTime = added[key] ?? (present.contains(word) ? 0 : -.infinity)
                let removeTime = removed[key] ?? -.infinity
                return addTime > removeTime
            }
        }

        return State(
            never: mergeList("never", local.never, remote.never),
            always: mergeList("always", local.always, remote.always),
            added: added,
            removed: removed
        )
    }
}
