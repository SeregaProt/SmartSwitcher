import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// Окно настроек (FR-10): боковая навигация по разделам (раздел 4.3 ТЗ).
@MainActor
public final class SettingsWindowController {
    private var window: NSWindow?
    private let dependencies: SettingsDependencies

    public init(
        preferences: Preferences,
        diary: DiaryService,
        importExport: ImportExportService,
        updates: UpdateService,
        notifications: NotificationService,
        license: LicenseService,
        stats: StatisticsService,
        personal: PersonalDictionary
    ) {
        dependencies = SettingsDependencies(
            preferences: preferences,
            diary: diary,
            importExport: importExport,
            updates: updates,
            notifications: notifications,
            license: license,
            stats: stats,
            personal: personal
        )
    }

    public func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(deps: dependencies))
            let window = NSWindow(contentViewController: hosting)
            window.title = L10n.text("settings.title", "Настройки SmartSwitcher")
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 780, height: 540))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsDependencies {
    let preferences: Preferences
    let diary: DiaryService
    let importExport: ImportExportService
    let updates: UpdateService
    let notifications: NotificationService
    let license: LicenseService
    let stats: StatisticsService
    let personal: PersonalDictionary
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general, languages, hotkeys, apps, words, expansion, statistics, diary, privacy, updates, account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return L10n.text("settings.tab.general", "Общие")
        case .languages: return L10n.text("settings.tab.languages", "Языки")
        case .hotkeys: return L10n.text("settings.tab.hotkeys", "Хоткеи")
        case .apps: return L10n.text("settings.tab.apps", "Приложения")
        case .words: return L10n.text("settings.tab.words", "Слова")
        case .expansion: return L10n.text("settings.tab.expansion", "Автозамена")
        case .statistics: return L10n.text("settings.tab.statistics", "Статистика")
        case .diary: return L10n.text("settings.tab.diary", "Дневник")
        case .privacy: return L10n.text("settings.tab.privacy", "Приватность")
        case .updates: return L10n.text("settings.tab.updates", "Обновления")
        case .account: return L10n.text("settings.tab.account", "Аккаунт")
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .languages: return "globe"
        case .hotkeys: return "keyboard"
        case .apps: return "square.grid.2x2"
        case .words: return "textformat.abc"
        case .expansion: return "arrow.right.square"
        case .statistics: return "chart.bar"
        case .diary: return "book.closed"
        case .privacy: return "lock.shield"
        case .updates: return "arrow.down.circle"
        case .account: return "person.crop.circle"
        }
    }
}

struct SettingsView: View {
    let deps: SettingsDependencies
    @State private var section: SettingsSection? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $section) { item in
                Label(item.title, systemImage: item.icon).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            detail(for: section ?? .general)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 720, minHeight: 500)
    }

    @ViewBuilder
    private func detail(for section: SettingsSection) -> some View {
        switch section {
        case .general:
            GeneralSettingsTab(preferences: deps.preferences, importExport: deps.importExport, notifications: deps.notifications)
        case .languages:
            LanguagesSettingsTab(preferences: deps.preferences)
        case .hotkeys:
            HotkeysSettingsTab(preferences: deps.preferences)
        case .apps:
            AppsSettingsTab(preferences: deps.preferences)
        case .words:
            WordsSettingsTab(preferences: deps.preferences)
        case .expansion:
            ExpansionSettingsTab(preferences: deps.preferences)
        case .statistics:
            StatisticsSettingsTab(stats: deps.stats)
        case .diary:
            DiarySettingsTab(preferences: deps.preferences, diary: deps.diary)
        case .privacy:
            PrivacySettingsTab(preferences: deps.preferences, diary: deps.diary, stats: deps.stats, personal: deps.personal)
        case .updates:
            UpdatesSettingsTab(preferences: deps.preferences, updates: deps.updates)
        case .account:
            AccountSettingsTab(license: deps.license)
        }
    }
}

/// Отметка платной функции (раздел 22).
private struct ProBadge: View {
    var body: some View {
        Text("Pro")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.accentColor.opacity(0.2)))
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
            Section {
                Toggle(L10n.text("settings.autocorrect", "Автоматически исправлять раскладку"), isOn: $preferences.enabled)
                Toggle(L10n.text("settings.learn", "Учиться на моём наборе (личный словарь)"), isOn: $preferences.learnFromTyping)
                Toggle(isOn: $preferences.reliableMode) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.text("settings.reliable", "Надёжный режим"))
                        Text(L10n.text("settings.reliable.note", "Ввод придерживается на миллисекунды, пока исправляется слово: быстрый набор не смешивается с перенабором, а слово перед Enter тоже исправляется. Использует активный перехват клавиатуры (не дольше 0,5 с)."))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Section(L10n.text("settings.feedback", "Обратная связь")) {
                Toggle(L10n.text("settings.hud", "Показывать раскладку у курсора"), isOn: $preferences.hudEnabled)
                Toggle(L10n.text("settings.sound", "Звук при исправлении"), isOn: $preferences.soundEnabled)
                Toggle(L10n.text("settings.notifications", "Уведомление при переключении"), isOn: $preferences.notificationsEnabled)
                    .onChange(of: preferences.notificationsEnabled) { enabled in
                        if enabled { notifications.requestAuthorizationIfNeeded() }
                    }
            }
            Section {
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
            }

            Section(L10n.text("settings.importexport", "Конфигурация")) {
                HStack {
                    Toggle(L10n.text("settings.sync", "Синхронизировать настройки через iCloud"), isOn: $preferences.syncEnabled)
                        .disabled(!preferences.proUnlocked)
                    ProBadge()
                }
                Text(L10n.text("settings.sync.note", "Синхронизируются только настройки и правила — никогда набранный текст. Списки слов объединяются между устройствами. Работает в подписанной релизной сборке."))
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

// MARK: - Приложения (режимы)

private struct AppsSettingsTab: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("settings.apps.note", "По умолчанию SmartSwitcher исправляет раскладку везде. Для отдельных приложений можно оставить только ручное исправление (Double-Shift, хоткеи выделения) или выключить его полностью."))
                .font(.callout)
                .foregroundColor(.secondary)
            AppListEditor(
                title: L10n.text("settings.apps.manual", "Только вручную (терминалы, IDE):"),
                apps: $preferences.manualOnlyApps
            )
            AppListEditor(
                title: L10n.text("settings.apps.off", "Выключено полностью (менеджеры паролей):"),
                apps: $preferences.excludedApps
            )
        }
        .padding()
    }
}

private struct AppListEditor: View {
    let title: String
    @Binding var apps: [String]
    @State private var selected: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            List(selection: $selected) {
                ForEach(apps, id: \.self) { bundleID in
                    HStack {
                        Text(Self.displayName(for: bundleID))
                        Spacer()
                        Text(bundleID).font(.caption).foregroundColor(.secondary)
                    }
                    .tag(bundleID)
                }
            }
            .frame(minHeight: 110)
            HStack {
                Button(L10n.text("settings.app.add", "Добавить приложение…")) { addApp() }
                Button(L10n.text("settings.app.remove", "Удалить")) {
                    if let selected { apps.removeAll { $0 == selected } }
                    selected = nil
                }
                .disabled(selected == nil)
            }
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        if !apps.contains(bundleID) { apps.append(bundleID) }
    }

    private static func displayName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
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

// MARK: - Статистика

private struct StatisticsSettingsTab: View {
    @ObservedObject var stats: StatisticsService

    var body: some View {
        let total = stats.total
        let today = stats.day()
        let week = stats.lastDays(14)
        let maxValue = max(1, week.map { $0.day.count(.auto) + $0.day.count(.manual) }.max() ?? 1)

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                StatTile(title: L10n.text("stats.today", "Сегодня"), value: today.count(.auto) + today.count(.manual))
                StatTile(title: L10n.text("stats.auto", "Авто-исправлений"), value: total.count(.auto))
                StatTile(title: L10n.text("stats.manual", "Вручную"), value: total.count(.manual))
                StatTile(title: L10n.text("stats.undo", "Откатов"), value: total.count(.undo))
                StatTile(title: L10n.text("stats.saved", "Сэкономлено нажатий"), value: total.savedKeystrokes)
            }

            Text(L10n.text("stats.chart", "Исправления за 14 дней"))
                .font(.headline)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(week.enumerated()), id: \.offset) { _, entry in
                    let value = entry.day.count(.auto) + entry.day.count(.manual)
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.accentColor)
                            .frame(width: 22, height: max(2, CGFloat(value) / CGFloat(maxValue) * 120))
                            .help("\(value)")
                        Text(entry.date, format: .dateTime.day())
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(height: 150, alignment: .bottom)

            Text(L10n.text("stats.privacy", "Хранятся только счётчики по дням (до 90 дней) — ни одного слова."))
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding()
    }
}

private struct StatTile: View {
    let title: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)").font(.title2.weight(.semibold)).monospacedDigit()
            Text(title).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
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
    let stats: StatisticsService
    let personal: PersonalDictionary
    @State private var clearedMessage: String?
    @State private var learnedCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                L10n.text("settings.privacy.title", "Набранный текст никогда не покидает устройство"),
                systemImage: "checkmark.shield"
            )
            Text(L10n.text("settings.privacy.body", "SmartSwitcher обрабатывает ввод только в оперативной памяти. Текст не сохраняется на диск (кроме дневника, если вы включили его явно), не отправляется в сеть и не попадает в логи. Поля паролей и режим защищённого ввода игнорируются автоматически."))
                .font(.callout)
                .foregroundColor(.secondary)

            Text(String(
                format: L10n.text("settings.privacy.personal", "Личный словарь: %d слов (хранятся только хеши)."),
                learnedCount
            ))
            .font(.callout)

            HStack {
                Button(L10n.text("settings.privacy.clearPersonal", "Очистить личный словарь")) {
                    personal.clear()
                    learnedCount = 0
                }
                Button(L10n.text("settings.privacy.clearStats", "Сбросить статистику")) {
                    stats.reset()
                }
            }

            Button(L10n.text("settings.privacy.clear", "Очистить все локальные данные")) {
                diary.clear()
                personal.clear()
                stats.reset()
                learnedCount = 0
                preferences.diaryEnabled = false
                preferences.neverCorrectWords = []
                preferences.alwaysCorrectWords = []
                preferences.excludedApps = Preferences.defaultExcludedApps
                preferences.manualOnlyApps = Preferences.defaultManualOnlyApps
                clearedMessage = L10n.text("settings.privacy.cleared", "Локальные данные очищены: дневник, личный словарь и статистика удалены, правила сброшены.")
            }
            if let clearedMessage {
                Text(clearedMessage).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
        .onAppear { learnedCount = personal.learnedCount }
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
            Text(L10n.text("settings.languages.note", "Исправление выполняется только в активные раскладки. Поддерживаются любые варианты раскладок macOS: «Русская» и «Русская – ПК», ABC, British, Dvorak, Colemak — таблицы строятся по вашим установленным раскладкам."))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .formStyle(.grouped)
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
            Section(L10n.text("settings.hotkey.shift", "Shift")) {
                Toggle(L10n.text("settings.hotkey.double", "Double-Shift — исправить последнее слово"), isOn: $preferences.doubleShiftFixEnabled)
                Toggle(L10n.text("settings.hotkey.undo", "Double-Shift откатывает авто-исправление и запоминает слово"), isOn: $preferences.undoLastEnabled)
                Toggle(L10n.text("settings.hotkey.single", "Single-Shift — сменить раскладку (экспериментально)"), isOn: $preferences.singleShiftSwitchEnabled)
                HStack {
                    Text(L10n.text("settings.hotkey.window", "Окно двойного нажатия"))
                    Slider(value: $preferences.shiftGestureWindow, in: 0.2...0.6, step: 0.05)
                    Text(String(format: "%.0f мс", preferences.shiftGestureWindow * 1000))
                        .monospacedDigit()
                        .frame(width: 60, alignment: .trailing)
                }
            }
            Section(L10n.text("settings.hotkey.backspace.section", "Откат")) {
                Toggle(isOn: $preferences.backspaceUndoEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.text("settings.hotkey.backspace", "Backspace сразу после исправления отменяет его"))
                        Text(L10n.text("settings.hotkey.backspace.note", "Удобно, но мешает стереть пробел после слова, чтобы поставить запятую."))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Section(L10n.text("settings.hotkey.selection", "Выделенный текст")) {
                Toggle(L10n.text("settings.hotkey.selection.enable", "Горячие клавиши для выделения"), isOn: $preferences.selectionHotkeysEnabled)
                LabeledContent(L10n.text("settings.hotkey.sel.layout", "Сменить раскладку"), value: "⌃⌥K")
                LabeledContent(L10n.text("settings.hotkey.sel.case", "Инвертировать регистр"), value: "⌃⌥U")
                LabeledContent(L10n.text("settings.hotkey.sel.translit", "Транслитерировать"), value: "⌃⌥T")
            }
            Text(L10n.text("settings.hotkey.note", "Single-Shift удобен, но может срабатывать ложно при обычном наборе заглавных — включайте осознанно."))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .formStyle(.grouped)
    }
}

// MARK: - Автозамена (FR-7, Pro)

private struct ExpansionSettingsTab: View {
    @ObservedObject var preferences: Preferences
    @State private var selected: String?
    @State private var newShortcut = ""
    @State private var newExpansion = ""

    private var sortedKeys: [String] { preferences.expansionRules.keys.sorted() }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle(L10n.text("settings.expansion.enable", "Включить автозамену текста"), isOn: $preferences.textExpansionEnabled)
                ProBadge()
            }
            .disabled(!preferences.proUnlocked)
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
                    if license.isDevBuild {
                        Text(L10n.text("account.dev", "Сборка для разработки: функции Pro открыты."))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Text(L10n.text("account.about", "Ядро (детект и переключение раскладки, хоткеи, личный словарь) бесплатно и открыто. План Pro добавляет синхронизацию через iCloud, автозамену текста и приоритетную поддержку."))
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
    @State private var status: String?
    @State private var availableURL: URL?
    @State private var checking = false

    var body: some View {
        Form {
            LabeledContent(L10n.text("settings.updates.current", "Текущая версия"), value: updates.currentVersion)
            Picker(L10n.text("settings.updates.channel", "Канал обновлений"), selection: $preferences.updateChannel) {
                Text(L10n.text("settings.updates.stable", "Стабильный")).tag("stable")
                Text(L10n.text("settings.updates.beta", "Бета")).tag("beta")
            }
            Toggle(L10n.text("settings.updates.auto", "Проверять обновления автоматически (раз в сутки)"), isOn: $preferences.autoCheckUpdates)
                .disabled(!updates.isConfigured)
            HStack {
                Button(L10n.text("settings.updates.check", "Проверить сейчас")) { check() }
                    .disabled(checking || !updates.isConfigured)
                if checking { ProgressView().controlSize(.small) }
                if let availableURL {
                    Button(L10n.text("settings.updates.open", "Открыть страницу релиза")) {
                        NSWorkspace.shared.open(availableURL)
                    }
                }
            }
            if let status {
                Text(status).font(.caption).foregroundColor(.secondary)
            }
            Text(updates.isConfigured
                ? L10n.text("settings.updates.note", "Новые версии публикуются в GitHub Releases. Автоматическая установка через Sparkle появится в подписанной релизной сборке.")
                : L10n.text("settings.updates.unconfigured", "Источник обновлений не настроен в этой сборке."))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .formStyle(.grouped)
    }

    private func check() {
        checking = true
        status = nil
        availableURL = nil
        updates.check { result in
            checking = false
            switch result {
            case .upToDate:
                status = L10n.text("settings.updates.uptodate", "У вас последняя версия.")
            case let .available(version, url):
                status = String(format: L10n.text("settings.updates.available", "Доступна версия %@."), version)
                availableURL = url
            case .failed:
                status = L10n.text("settings.updates.failed", "Не удалось проверить обновления.")
            }
        }
    }
}
