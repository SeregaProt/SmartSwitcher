import CryptoKit
import Foundation

/// Дневник исправлений (FR-11). Выключен по умолчанию.
///
/// Приватность (раздел 11 ТЗ):
/// - записи шифруются AES-GCM, ключ — в Keychain;
/// - файл живёт только локально (Application Support), в сеть не уходит;
/// - дневник очищается одной кнопкой; при выключении запись прекращается.
public final class DiaryService {
    public struct Entry: Codable, Equatable {
        public let date: Date
        public let original: String
        public let corrected: String
        public let app: String?
        public let manual: Bool
    }

    private let preferences: Preferences
    private let queue = DispatchQueue(label: "com.smartswitcher.diary", qos: .utility)
    private let keychainAccount = "diary-key"

    public init(preferences: Preferences) {
        self.preferences = preferences
    }

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SmartSwitcher", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("diary.sealed")
    }

    private func key() -> SymmetricKey {
        if let data = KeychainHelper.read(account: keychainAccount) {
            return SymmetricKey(data: data)
        }
        let key = SymmetricKey(size: .bits256)
        KeychainHelper.write(account: keychainAccount, data: key.withUnsafeBytes { Data($0) })
        return key
    }

    public func record(original: String, corrected: String, app: String?, manual: Bool) {
        guard preferences.diaryEnabled else { return }
        let entry = Entry(date: Date(), original: original, corrected: corrected, app: app, manual: manual)
        queue.async { [self] in
            var entries = readAll()
            entries.append(entry)
            // Ограничение размера: храним последние 1000 записей.
            if entries.count > 1000 {
                entries.removeFirst(entries.count - 1000)
            }
            writeAll(entries)
        }
    }

    public func entries() -> [Entry] {
        queue.sync { readAll() }
    }

    public func clear() {
        queue.sync {
            try? FileManager.default.removeItem(at: fileURL)
            KeychainHelper.delete(account: keychainAccount)
        }
        Log.app.info("Дневник очищен")
    }

    // MARK: - Private

    private func readAll() -> [Entry] {
        guard let sealed = try? Data(contentsOf: fileURL),
              let box = try? AES.GCM.SealedBox(combined: sealed),
              let data = try? AES.GCM.open(box, using: key()),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            return []
        }
        return entries
    }

    private func writeAll(_ entries: [Entry]) {
        guard let data = try? JSONEncoder().encode(entries),
              let sealed = try? AES.GCM.seal(data, using: key()).combined else {
            return
        }
        try? sealed.write(to: fileURL, options: .atomic)
    }
}
