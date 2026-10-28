import Foundation

/// Статистика исправлений (только счётчики — ни одного слова, раздел 11).
/// Хранится локально по дням, не дольше 90 дней.
public final class StatisticsService: ObservableObject {
    public enum Kind: String, CaseIterable, Sendable {
        case auto
        case manual
        case undo
        case expansion
    }

    public struct Day: Equatable {
        public var counts: [Kind: Int] = [:]
        /// Оценка сэкономленных нажатий (стереть + переключить + перенабрать).
        public var savedKeystrokes = 0

        public func count(_ kind: Kind) -> Int { counts[kind] ?? 0 }
    }

    private static let storageKey = "statistics.days"
    private static let retentionDays = 90

    @Published public private(set) var days: [String: Day] = [:]
    private let defaults: UserDefaults
    private let calendar = Calendar(identifier: .gregorian)
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        days = Self.decode(defaults.dictionary(forKey: Self.storageKey) ?? [:])
    }

    /// Учесть событие. Безопасно с любого потока (запись — на главном).
    public func record(_ kind: Kind, savedKeystrokes: Int = 0, at date: Date = Date()) {
        let key = formatter.string(from: date)
        let apply = { [weak self] in
            guard let self else { return }
            var day = self.days[key] ?? Day()
            day.counts[kind, default: 0] += 1
            day.savedKeystrokes += savedKeystrokes
            self.days[key] = day
            self.prune(relativeTo: date)
            self.persist()
        }
        if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
    }

    public func day(_ date: Date = Date()) -> Day {
        days[formatter.string(from: date)] ?? Day()
    }

    /// Последние `count` дней, от старых к новым (для графика).
    public func lastDays(_ count: Int, until date: Date = Date()) -> [(date: Date, day: Day)] {
        (0..<count).reversed().compactMap { offset in
            guard let d = calendar.date(byAdding: .day, value: -offset, to: date) else { return nil }
            return (d, day(d))
        }
    }

    public var total: Day {
        days.values.reduce(into: Day()) { sum, day in
            for (kind, value) in day.counts { sum.counts[kind, default: 0] += value }
            sum.savedKeystrokes += day.savedKeystrokes
        }
    }

    public func reset() {
        days = [:]
        defaults.removeObject(forKey: Self.storageKey)
    }

    // MARK: - Private

    private func prune(relativeTo date: Date) {
        guard let cutoff = calendar.date(byAdding: .day, value: -Self.retentionDays, to: date) else { return }
        let cutoffKey = formatter.string(from: cutoff)
        days = days.filter { $0.key >= cutoffKey }
    }

    private func persist() {
        var raw: [String: [String: Int]] = [:]
        for (key, day) in days {
            var entry: [String: Int] = ["saved": day.savedKeystrokes]
            for (kind, value) in day.counts { entry[kind.rawValue] = value }
            raw[key] = entry
        }
        defaults.set(raw, forKey: Self.storageKey)
    }

    private static func decode(_ raw: [String: Any]) -> [String: Day] {
        var result: [String: Day] = [:]
        for (key, value) in raw {
            guard let entry = value as? [String: Int] else { continue }
            var day = Day()
            day.savedKeystrokes = entry["saved"] ?? 0
            for kind in Kind.allCases {
                if let count = entry[kind.rawValue] { day.counts[kind] = count }
            }
            result[key] = day
        }
        return result
    }
}
