import Combine
import Foundation

/// Синхронизация настроек и правил между устройствами через iCloud
/// (раздел 15 ТЗ, план Pro). Через `NSUbiquitousKeyValueStore` хранится один
/// снапшот конфигурации (формат `ImportExportService.Snapshot` + метка).
///
/// ВАЖНО (раздел 15): синхронизируются только настройки — никогда набранный
/// текст или история ввода. Списки слов сливаются по меткам времени
/// (`WordRuleMerge`), остальное — last-write-wins; флаг «включено» локален.
///
/// Без iCloud-entitlement KVS-операции безопасно ничего не делают — функция
/// включается в релизной сборке с provisioning profile (ADR-0007).
///
/// `@unchecked Sendable`: всё состояние трогается только на главном потоке
/// (внешние уведомления KVS перенаправляются на `DispatchQueue.main`).
public final class SyncService: @unchecked Sendable {
    private enum Key {
        static let snapshot = "config.snapshot"
        static let timestamp = "config.timestamp"
        static let lastApplied = "config.lastAppliedTimestamp"
    }

    private let preferences: Preferences
    private let importExport: ImportExportService
    private let store = NSUbiquitousKeyValueStore.default
    private var cancellable: AnyCancellable?
    private var isApplyingRemote = false
    private var pushWorkItem: DispatchWorkItem?
    public private(set) var isRunning = false

    public init(preferences: Preferences, importExport: ImportExportService) {
        self.preferences = preferences
        self.importExport = importExport
    }

    /// Включить/выключить без перезапуска приложения (главный поток).
    public func setEnabled(_ enabled: Bool) {
        if enabled { start() } else { stop() }
    }

    /// Запуск синхронизации: подписка на внешние изменения и на локальные правки.
    public func start() {
        guard !isRunning else { return }
        isRunning = true

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
        schedulePush()

        Log.app.info("Синхронизация iCloud включена")
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        NotificationCenter.default.removeObserver(self)
        cancellable = nil
        pushWorkItem?.cancel()
        Log.app.info("Синхронизация iCloud выключена")
    }

    // MARK: - Push (локальные → iCloud)

    private func schedulePush() {
        guard isRunning, !isApplyingRemote else { return }
        pushWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.push() }
        pushWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func push() {
        guard isRunning, let data = try? importExport.exportData() else { return }
        let now = Date().timeIntervalSince1970
        store.set(data, forKey: Key.snapshot)
        store.set(now, forKey: Key.timestamp)
        store.synchronize()
        // Собственный снапшот не нужно применять обратно при следующем старте.
        UserDefaults.standard.set(now, forKey: Key.lastApplied)
        Log.app.info("Настройки выгружены в iCloud (\(data.count) байт)")
    }

    // MARK: - Pull (iCloud → локальные)

    @objc private func externalChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.applyRemoteIfNewer() }
    }

    private func applyRemoteIfNewer() {
        guard let data = store.data(forKey: Key.snapshot) else { return }
        let remoteTime = store.double(forKey: Key.timestamp)
        let localTime = UserDefaults.standard.double(forKey: Key.lastApplied)
        guard remoteTime > localTime else { return }

        isApplyingRemote = true
        defer { isApplyingRemote = false }
        do {
            try importExport.importData(data, mode: .merge)
            UserDefaults.standard.set(remoteTime, forKey: Key.lastApplied)
            Log.app.info("Настройки применены из iCloud (метка \(remoteTime))")
        } catch {
            Log.app.error("Снапшот iCloud отклонён: \(error.localizedDescription)")
        }
        // Слияние могло добавить локальные слова, которых нет в облаке, —
        // только тогда отправляем обратно (иначе устройства играли бы в пинг-понг).
        if let local = try? importExport.exportData(), Self.differs(local, data) {
            schedulePush()
        }
    }

    /// Отличаются ли снапшоты по существу (флаг «включено» локален).
    static func differs(_ lhs: Data, _ rhs: Data) -> Bool {
        let decoder = JSONDecoder()
        guard var a = try? decoder.decode(ImportExportService.Snapshot.self, from: lhs),
              let b = try? decoder.decode(ImportExportService.Snapshot.self, from: rhs) else {
            return true
        }
        a.enabled = b.enabled
        return a != b
    }
}
