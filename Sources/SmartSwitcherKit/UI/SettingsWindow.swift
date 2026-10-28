import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// Окно настроек (FR-10), SwiftUI с вкладками (раздел 4.3 ТЗ).
public final class SettingsWindowController {
    private var window: NSWindow?
    private let preferences: Preferences
    private let diary: DiaryService
    private let importExport: ImportExportService
    private let updates: UpdateService
    private let notifications: NotificationService
    private let license: LicenseService

    public init(
        preferences: Preferences,
        diary: DiaryService,
        importExport: ImportExportService,
        updates: UpdateService,
        notifications: NotificationService,
        license: LicenseService
    ) {
        self.preferences = preferences
        self.diary = diary
        self.importExport = importExport
        self.updates = updates
        self.notifications = notifications
        self.license = license
    }

    public func show() {
        if window == nil {
            let view = SettingsView(
                preferences: preferences,
                diary: diary,
                importExport: importExport,
                updates: updates,
                notifications: notifications,
                license: license
            )
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.title = L10n.text("settings.title", "Настройки SmartSwitcher")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    let diary: DiaryService
    let importExport: ImportExportService
    let updates: UpdateService
    let notifications: NotificationService
    @ObservedObject var license: LicenseService

    var body: some View {
        TabView {
            GeneralSettingsTab(preferences: preferences, importExport: importExport, notifications: notifications)
                .tabItem { Label(L10n.text("settings.tab.general", "Общие"), systemImage: "gearshape") }
            LanguagesSettingsTab(preferences: preferences)
                .tabItem { Label(L10n.text("settings.tab.languages", "Языки"), systemImage: "globe") }
            HotkeysSettingsTab(preferences: preferences)
                .tabItem { Label(L10n.text("settings.tab.hotkeys", "Хоткеи"), systemImage: "keyboard") }
            ExclusionsSettingsTab(preferences: preferences)
                .tabItem { Label(L10n.text("settings.tab.exclusions", "Исключения"), systemImage: "hand.raised") }
            WordsSettingsTab(preferences: preferences)
                .tabItem { Label(L10n.text("settings.tab.words", "Слова"), systemImage: "textformat.abc") }
            ExpansionSettingsTab(preferences: preferences)
                .tabItem { Label(L10n.text("settings.tab.expansion", "Автозамена"), systemImage: "arrow.right.square") }
            DiarySettingsTab(preferences: preferences, diary: diary)
                .tabItem { Label(L10n.text("settings.tab.diary", "Дневник"), systemImage: "book.closed") }
            UpdatesSettingsTab(preferences: preferences, updates: updates)
                .tabItem { Label(L10n.text("settings.tab.updates", "Обновления"), systemImage: "arrow.down.circle") }
            PrivacySettingsTab(preferences: preferences, diary: diary)
                .tabItem { Label(L10n.text("settings.tab.privacy", "Приватность"), systemImage: "lock.shield") }
            AccountSettingsTab(license: license)
                .tabItem { Label(L10n.text("settings.tab.account", "Аккаунт"), systemImage: "person.crop.circle") }
        }
        .frame(width: 580, height: 460)
    }
}

// MARK: - Общие

private struct GeneralSettingsTab: View {
    @ObservedObject var preferences: Preferences
    let importExport: ImportExportService
    let notifications: NotificationService
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?
    @State private var ioMessage: String?

    var body: some View {
        Form {
            Toggle(L10n.text("settings.autocorrect", "Автоматически исправлять раскладку"), isOn: $preferences.enabled)
            Toggle(L10n.text("settings.sound", "Звук при исправлении"), isOn: $preferences.soundEnabled)
            Toggle(L10n.text("settings.notifications", "Уведомление при переключении"), isOn: $preferences.notificationsEnabled)
                .onChange(of: preferences.notificationsEnabled) { enabled in
                    if enabled { notifications.requestAuthorizationIfNeeded() }
                }
            Toggle(L10n.text("settings.launch", "Запускать при входе в систему"), isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                        loginItemError = nil
                    } catch {
                        loginItemError = String(
                            format: L10n.text("settings.launch.error", "Не удалось изменить автозапуск: %@"),
                            error.localizedDescription
                        )
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            if let loginItemError {
                Text(loginItemError).font(.caption).foregroundColor(.red)
            }


            Section(L10n.text("settings.importexport", "Конфигурация")) {
                Toggle(L10n.text("settings.sync", "Синхронизировать настройки через iCloud"), isOn: $preferences.syncEnabled)
                Text(L10n.text("settings.sync.note", "Синхронизируются только настройки и правила — никогда набранный текст. Включается в подписанной релизной сборке."))
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    Button(L10n.text("settings.export", "Экспортировать…")) { exportConfig() }
                    Button(L10n.text("settings.import", "Импортировать…")) { importConfig() }
                }
                if let ioMessage {
                    Text(ioMessage).font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func exportConfig() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "SmartSwitcher.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try importExport.exportData().write(to: url)
            ioMessage = L10n.text("export.done", "Конфигурация экспортирована.")
        } catch {
            ioMessage = error.localizedDescription
        }
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try importExport.importData(try Data(contentsOf: url))
            ioMessage = L10n.text("import.done", "Конфигурация импортирована.")
        } catch {
            ioMessage = error.localizedDescription
        }
    }
}

// MARK: - Исключения приложений

private struct ExclusionsSettingsTab: View {
    @ObservedObject var preferences: Preferences
    @State private var selectedApp: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("settings.excluded.apps", "Приложения, в которых исправление отключено:"))
                .font(.headline)
            List(selection: $selectedApp) {
                ForEach(preferences.excludedApps, id: \.self) { app in
                    Text(app).tag(app)
                }
            }
            HStack {
                Button(L10n.text("settings.app.add", "Добавить приложение…")) { addApp() }
                Button(L10n.text("settings.app.remove", "Удалить")) {
                    if let selectedApp {
                        preferences.excludedApps.removeAll { $0 == selectedApp }
                    }
                }
                .disabled(selectedApp == nil)
            }
        }
        .padding()
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url),
              let bundleID = bundle.bundleIdentifier else { return }
        if !preferences.excludedApps.contains(bundleID) {
            preferences.excludedApps.append(bundleID)
        }
    }
}

// MARK: - Правила слов

private struct WordsSettingsTab: View {
    @ObservedObject var preferences: Preferences
    @State private var selectedNever: String?
    @State private var selectedAlways: String?
    @State private var newNever = ""
    @State private var newAlways = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("settings.words.never", "Никогда не исправлять (сюда же пишет самообучение):"))
                .font(.headline)
            List(selection: $selectedNever) {
                ForEach(preferences.neverCorrectWords, id: \.self) { Text($0).tag($0) }
            }
            .frame(minHeight: 80)
            wordEditor(
                text: $newNever,
                selection: $selectedNever,
                words: $preferences.neverCorrectWords
            )

            Text(L10n.text("settings.words.always", "Всегда исправлять:"))
                .font(.headline)
            List(selection: $selectedAlways) {
                ForEach(preferences.alwaysCorrectWords, id: \.self) { Text($0).tag($0) }
            }
            .frame(minHeight: 80)
            wordEditor(
                text: $newAlways,
                selection: $selectedAlways,
                words: $preferences.alwaysCorrectWords
            )
        }
        .padding()
    }

    @ViewBuilder
    private func wordEditor(
        text: Binding<String>,
        selection: Binding<String?>,
        words: Binding<[String]>
    ) -> some View {
        HStack {
            TextField(L10n.text("settings.words.placeholder", "слово"), text: text)
                .frame(width: 160)
            Button(L10n.text("settings.words.add", "Добавить")) {
                let word = WordRulesManager.normalize(text.wrappedValue)
                if !word.isEmpty, !words.wrappedValue.contains(word) {
                    words.wrappedValue.append(word)
                }
                text.wrappedValue = ""
            }
            Button(L10n.text("settings.words.remove", "Удалить слово")) {
                if let selected = selection.wrappedValue {
                    words.wrappedValue.removeAll { $0 == selected }
                    selection.wrappedValue = nil
                }
            }
            .disabled(selection.wrappedValue == nil)
        }
    }
}

// MARK: - Дневник

private struct DiarySettingsTab: View {
    @ObservedObject var preferences: Preferences
    let diary: DiaryService
    @State private var entries: [DiaryService.Entry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(L10n.text("settings.diary.enable", "Вести дневник исправлений"), isOn: $preferences.diaryEnabled)
            Text(L10n.text("settings.diary.warning", "Дневник хранит исправленные слова на диске (в зашифрованном виде, ключ — в Keychain). Включайте, только если готовы к локальному хранению этой истории. В сеть данные не передаются."))
                .font(.caption)
                .foregroundColor(.secondary)

            if entries.isEmpty {
                Text(L10n.text("settings.diary.empty", "Дневник пуст"))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(Array(entries.enumerated().reversed()), id: \.offset) { _, entry in
                    HStack {
                        Text(entry.original).strikethrough()
                        Image(systemName: "arrow.right")
                        Text(entry.corrected)
                        Spacer()
                        Text(entry.date, style: .time).foregroundColor(.secondary)
                    }
                }
            }

            Button(L10n.text("settings.diary.clear", "Очистить дневник")) {
                diary.clear()
                entries = []
            }
        }
        .padding()
        .onAppear { entries = diary.entries() }
    }
}

// MARK: - Приватность

private struct PrivacySettingsTab: View {
    @ObservedObject var preferences: Preferences
    let diary: DiaryService
    @State private var clearedMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                L10n.text("settings.privacy.title", "Набранный текст никогда не покидает устройство"),
                systemImage: "checkmark.shield"
            )
            Text(L10n.text("settings.privacy.body", "SmartSwitcher обрабатывает ввод только в оперативной памяти. Текст не сохраняется на диск (кроме дневника, если вы включили его явно), не отправляется в сеть и не попадает в логи. Поля паролей (secure text fields) игнорируются автоматически."))
                .font(.callout)
                .foregroundColor(.secondary)

            Button(L10n.text("settings.privacy.clear", "Очистить локальные данные")) {
                diary.clear()
                preferences.diaryEnabled = false
                preferences.neverCorrectWords = []
                preferences.alwaysCorrectWords = []
                preferences.excludedApps = Preferences.defaultExcludedApps
                clearedMessage = L10n.text("settings.privacy.cleared", "Локальные данные очищены: дневник удалён, правила и исключения сброшены.")
            }
            if let clearedMessage {
                Text(clearedMessage).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
    }
}

// MARK: - Языки детекта

private struct LanguagesSettingsTab: View {
    @ObservedObject var preferences: Preferences

    private func binding(for layout: Layout) -> Binding<Bool> {
        Binding(
            get: { preferences.detectionLanguages.contains(layout.rawValue) },
            set: { isOn in
                var set = preferences.detectionLanguages
                if isOn {
                    if !set.contains(layout.rawValue) { set.append(layout.rawValue) }
                } else {
                    set.removeAll { $0 == layout.rawValue }
                }
                // Хотя бы один язык должен остаться активным.
                if !set.isEmpty { preferences.detectionLanguages = set }
            }
        )
    }

    var body: some View {
        Form {
            Section(L10n.text("settings.languages.active", "Активные раскладки детекта")) {
                ForEach(Layout.allCases, id: \.self) { layout in
                    Toggle(languageName(layout), isOn: binding(for: layout))
                        .accessibilityLabel(languageName(layout))
                }
            }
            Text(L10n.text("settings.languages.note", "Исправление выполняется только в активные раскладки. Языки интерфейса и языки детекта — независимы. Архитектура готова к добавлению новых раскладок."))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }

    private func languageName(_ layout: Layout) -> String {
        switch layout {
        case .ru: return L10n.text("language.ru", "Русский (RU)")
        case .en: return L10n.text("language.en", "English (EN)")
        }
    }
}

// MARK: - Хоткеи (FR-4)

private struct HotkeysSettingsTab: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        Form {
            Section {
                Toggle(L10n.text("settings.hotkey.double", "Double-Shift — исправить последнее слово"), isOn: $preferences.doubleShiftFixEnabled)
                Toggle(L10n.text("settings.hotkey.undo", "Double-Shift откатывает авто-исправление и запоминает слово"), isOn: $preferences.undoLastEnabled)
                Toggle(L10n.text("settings.hotkey.single", "Single-Shift — сменить раскладку (экспериментально)"), isOn: $preferences.singleShiftSwitchEnabled)
            }
            Section(L10n.text("settings.hotkey.window", "Окно двойного нажатия")) {
                HStack {
                    Slider(value: $preferences.shiftGestureWindow, in: 0.2...0.6, step: 0.05)
                    Text(String(format: "%.0f мс", preferences.shiftGestureWindow * 1000))
                        .monospacedDigit()
                        .frame(width: 60, alignment: .trailing)
                }
            }
            Text(L10n.text("settings.hotkey.note", "Single-Shift удобен, но может срабатывать ложно при обычном наборе заглавных — включайте осознанно."))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Автозамена (FR-7)

private struct ExpansionSettingsTab: View {
    @ObservedObject var preferences: Preferences
    @State private var selected: String?
    @State private var newShortcut = ""
    @State private var newExpansion = ""

    private var sortedKeys: [String] { preferences.expansionRules.keys.sorted() }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(L10n.text("settings.expansion.enable", "Включить автозамену текста"), isOn: $preferences.textExpansionEnabled)
            Text(L10n.text("settings.expansion.note", "Правило «сокращение → текст» применяется на границе слова. Пример: omw → on my way."))
                .font(.caption)
                .foregroundColor(.secondary)

            Table(of: ExpansionRow.self, selection: $selected) {
                TableColumn(L10n.text("settings.expansion.shortcut", "Сокращение")) { Text($0.shortcut) }
                TableColumn(L10n.text("settings.expansion.text", "Замена")) { Text($0.expansion) }
            } rows: {
                ForEach(sortedKeys, id: \.self) { key in
                    TableRow(ExpansionRow(shortcut: key, expansion: preferences.expansionRules[key] ?? ""))
                }
            }
            .frame(minHeight: 140)

            HStack {
                TextField(L10n.text("settings.expansion.shortcut", "Сокращение"), text: $newShortcut)
                    .frame(width: 120)
                Image(systemName: "arrow.right")
                TextField(L10n.text("settings.expansion.text", "Замена"), text: $newExpansion)
                Button(L10n.text("settings.words.add", "Добавить")) { add() }
                    .disabled(newShortcut.trimmingCharacters(in: .whitespaces).isEmpty || newExpansion.isEmpty)
                Button(L10n.text("settings.words.remove", "Удалить")) {
                    if let selected { preferences.expansionRules.removeValue(forKey: selected) }
                    selected = nil
                }
                .disabled(selected == nil)
            }
        }
        .padding()
    }

    private func add() {
        let key = newShortcut.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty, !newExpansion.isEmpty else { return }
        preferences.expansionRules[key] = newExpansion
        newShortcut = ""
        newExpansion = ""
    }

    private struct ExpansionRow: Identifiable {
        let shortcut: String
        let expansion: String
        var id: String { shortcut }
    }
}

// MARK: - Аккаунт / Лицензия (22)

private struct AccountSettingsTab: View {
    @ObservedObject var license: LicenseService
    @State private var key = ""
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: license.isPro ? "checkmark.seal.fill" : "person.crop.circle")
                    .foregroundColor(license.isPro ? .green : .secondary)
                    .font(.title2)
                VStack(alignment: .leading) {
                    Text(license.isPro
                        ? L10n.text("account.pro", "План Pro активен")
                        : L10n.text("account.free", "Бесплатный план"))
                        .font(.headline)
                    if license.isPro, !license.current.email.isEmpty {
                        Text(license.current.email).font(.caption).foregroundColor(.secondary)
                    }
                }
            }

            Text(L10n.text("account.about", "Ядро (детект и переключение раскладки) бесплатно и открыто. План Pro добавляет синхронизацию, расширенные функции и приоритетную поддержку."))
                .font(.callout)
                .foregroundColor(.secondary)

            if !license.isPro {
                Text(L10n.text("account.enter", "Введите лицензионный ключ:"))
                    .font(.subheadline)
                HStack {
                    TextField(L10n.text("account.key", "Лицензионный ключ"), text: $key)
                        .textFieldStyle(.roundedBorder)
                    Button(L10n.text("account.activate", "Активировать")) { activate() }
                        .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Button(L10n.text("account.restore", "Восстановить покупки")) { license.restore() }
                    .buttonStyle(.link)
            } else {
                Button(L10n.text("account.deactivate", "Деактивировать на этом Mac")) {
                    license.deactivate()
                }
            }

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundColor(isError ? .red : .green)
            }
            Spacer()
        }
        .padding()
    }

    private func activate() {
        do {
            _ = try license.activate(key: key)
            message = L10n.text("account.activated", "Лицензия активирована. Спасибо!")
            isError = false
            key = ""
        } catch {
            message = error.localizedDescription
            isError = true
        }
    }
}

// MARK: - Обновления (14)

private struct UpdatesSettingsTab: View {
    @ObservedObject var preferences: Preferences
    let updates: UpdateService

    var body: some View {
        Form {
            Picker(L10n.text("settings.updates.channel", "Канал обновлений"), selection: $preferences.updateChannel) {
                Text(L10n.text("settings.updates.stable", "Стабильный")).tag("stable")
                Text(L10n.text("settings.updates.beta", "Бета")).tag("beta")
            }
            Toggle(L10n.text("settings.updates.auto", "Проверять обновления автоматически"), isOn: $preferences.autoCheckUpdates)
            Button(L10n.text("settings.updates.check", "Проверить сейчас")) {
                updates.checkForUpdates()
            }
            Text(L10n.text("settings.updates.note", "Полная авто-установка через Sparkle появится в релизной версии. Сейчас проверка открывает страницу релизов."))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }
}
