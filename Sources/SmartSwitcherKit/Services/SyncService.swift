import Combine
import Foundation

/// Синхронизация настроек и правил между устройствами через iCloud
/// (раздел 15 ТЗ). Через `NSUbiquitousKeyValueStore` хранится один снапшот
/// конфигурации (формат `ImportExportService.Snapshot` + временная метка).
///
/// ВАЖНО (раздел 15): синхронизируются только настройки — никогда набранный
/// текст или история ввода. Разрешение конфликтов — last-write-wins по метке.
///
/// Без iCloud-entitlement (`com.apple.developer.ubiquity-kvstore-identifier`)
/// KVS-операции безопасно ничего не делают — функция включается в релизной
/// подписанной сборке (см. docs/adr/0007-sync.md).
public final class SyncService {
    private enum Key {
        static let snapshot = "config.snapshot"
        static let timestamp = "config.timestamp"
    }

    private let preferences: Preferences
    private let importExport: ImportExportService
    private let store = NSUbiquitousKeyValueStore.default
    private var cancellable: AnyCancellable?
    private var isApplyingRemote = false
    private var pushWorkItem: DispatchWorkItem?

    public init(preferences: Preferences, importExport: ImportExportService) {
        self.preferences = preferences
        self.importExport = importExport
    }

    /// Запуск синхронизации: подписка на внешние изменения и на локальные правки.
    public func start() {
        guard preferences.syncEnabled else { return }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(externalChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store
        )
        store.synchronize()
        applyRemoteIfNewer()

        // Локальные изменения настроек → отложенный push (дебаунс).
        cancellable = preferences.objectWillChange
            .sink { [weak self] in self?.schedulePush() }

        Log.app.info("Синхронизация iCloud включена")
    }

    public func stop() {
        NotificationCenter.default.removeObserver(self)
        cancellable = nil
        pushWorkItem?.cancel()
    }

    // MARK: - Push (локальные → iCloud)

    private func schedulePush() {
        guard preferences.syncEnabled, !isApplyingRemote else { return }
        pushWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.push() }
        pushWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func push() {
        guard let data = try? importExport.exportData() else { return }
        store.set(data, forKey: Key.snapshot)
        store.set(Date().timeIntervalSince1970, forKey: Key.timestamp)
        store.synchronize()
        Log.app.info("Настройки выгружены в iCloud (\(data.count) байт)")
    }

    // MARK: - Pull (iCloud → локальные)

    @objc private func externalChange(_ notification: Notification) {
        applyRemoteIfNewer()
    }

    private func applyRemoteIfNewer() {
        guard let data = store.data(forKey: Key.snapshot) else { return }
        let remoteTime = store.double(forKey: Key.timestamp)
        let localTime = UserDefaults.standard.double(forKey: "config.lastAppliedTimestamp")
        guard remoteTime > localTime else { return }

        isApplyingRemote = true
        try? importExport.importData(data)
        UserDefaults.standard.set(remoteTime, forKey: "config.lastAppliedTimestamp")
        // importData применяет изменения асинхронно на main — снимаем флаг после.
        DispatchQueue.main.async { [weak self] in self?.isApplyingRemote = false }
        Log.app.info("Настройки применены из iCloud (метка \(remoteTime))")
    }
}
