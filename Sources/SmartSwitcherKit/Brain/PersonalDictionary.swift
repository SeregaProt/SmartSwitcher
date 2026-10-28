import CryptoKit
import Foundation

/// Личный словарь (положительное самообучение, FR-6): слова, которые
/// пользователь набирает и оставляет без исправления, после нескольких
/// подтверждений считаются «своими» для раскладки — детектор их не трогает
/// и узнаёт как кандидатов при наборе в чужой раскладке.
///
/// Приватность (раздел 11): на диске хранятся только 64-битные солёные
/// хеши слов, а не сами слова; файл локальный и очищается одной кнопкой.
public final class PersonalDictionary {
    /// Сколько раз слово должно быть оставлено без правок, чтобы стать «своим».
    public static let confirmationsToLearn: UInt8 = 3
    private static let maxEntries = 20_000
    private static let saltKey = "personalDictionary.salt"

    private let storeURL: URL?
    private let salt: Data
    private let lock = NSLock()
    private var counts: [UInt64: UInt8] = [:]
    private var loaded = false
    private var saveScheduled = false
    private let ioQueue = DispatchQueue(label: "com.smartswitcher.personal", qos: .utility)

    /// - Parameter storeURL: nil — только в памяти (тесты).
    public init(storeURL: URL? = PersonalDictionary.defaultStoreURL, defaults: UserDefaults = .standard) {
        self.storeURL = storeURL
        if let existing = defaults.data(forKey: Self.saltKey), existing.count == 16 {
            salt = existing
        } else {
            let fresh = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
            defaults.set(fresh, forKey: Self.saltKey)
            salt = fresh
        }
    }

    public static var defaultStoreURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base.appendingPathComponent("SmartSwitcher", isDirectory: true)
            .appendingPathComponent("personal.bin")
    }

    public func contains(_ word: String, in layout: Layout) -> Bool {
        let key = hash(word, layout)
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        return (counts[key] ?? 0) >= Self.confirmationsToLearn
    }

    /// Слово оставлено пользователем без исправления — ещё одно подтверждение.
    public func noteKept(_ word: String, in layout: Layout) {
        let key = hash(word, layout)
        lock.lock()
        loadIfNeeded()
        let current = counts[key] ?? 0
        if current < .max { counts[key] = current + 1 }
        if counts.count > Self.maxEntries {
            // Вытесняем однократные наблюдения — они почти всегда шум.
            counts = counts.filter { $0.value > 1 }
        }
        lock.unlock()
        scheduleSave()
    }

    /// Пользователь исправил слово вручную — подтверждения сгорают.
    public func forget(_ word: String, in layout: Layout) {
        let key = hash(word, layout)
        lock.lock()
        loadIfNeeded()
        let removed = counts.removeValue(forKey: key) != nil
        lock.unlock()
        if removed { scheduleSave() }
    }

    public var learnedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        return counts.values.filter { $0 >= Self.confirmationsToLearn }.count
    }

    public func clear() {
        lock.lock()
        counts = [:]
        loaded = true
        lock.unlock()
        ioQueue.sync {
            if let storeURL { try? FileManager.default.removeItem(at: storeURL) }
        }
    }

    // MARK: - Private

    private func hash(_ word: String, _ layout: Layout) -> UInt64 {
        var input = salt
        input.append(Data("\(layout.rawValue):\(word.lowercased())".utf8))
        let digest = SHA256.hash(data: input)
        return digest.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }
    }

    /// Вызывается под `lock`.
    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let storeURL, let data = try? Data(contentsOf: storeURL) else { return }
        let bytes = [UInt8](data)
        let stride = 9
        var offset = 0
        while offset + stride <= bytes.count {
            var key: UInt64 = 0
            for i in 0..<8 { key |= UInt64(bytes[offset + i]) << (8 * UInt64(i)) }
            counts[key] = bytes[offset + 8]
            offset += stride
        }
    }

    private func scheduleSave() {
        guard storeURL != nil else { return }
        lock.lock()
        let alreadyScheduled = saveScheduled
        saveScheduled = true
        lock.unlock()
        guard !alreadyScheduled else { return }
        ioQueue.asyncAfter(deadline: .now() + 5) { [weak self] in self?.save() }
    }

    private func save() {
        lock.lock()
        saveScheduled = false
        var bytes: [UInt8] = []
        bytes.reserveCapacity(counts.count * 9)
        for (key, count) in counts {
            for i in 0..<8 { bytes.append(UInt8(truncatingIfNeeded: key >> (8 * UInt64(i)))) }
            bytes.append(count)
        }
        lock.unlock()
        guard let storeURL else { return }
        try? FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? Data(bytes).write(to: storeURL, options: .atomic)
    }
}
