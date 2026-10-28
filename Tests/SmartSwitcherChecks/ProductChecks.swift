import CoreGraphics
import CryptoKit
import Foundation
import SmartSwitcherKit

/// Проверки v0.4: настройки и режимы приложений, синхронизация, лицензия,
/// обновления, статистика, преобразования выделения, системные раскладки.
func runProductChecks() {
    func freshDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    suite("Режимы приложений (FR-5)") {
        var settings = EngineSettings()
        settings.excludedApps = ["com.1password.1password"]
        settings.manualOnlyApps = ["com.apple.Terminal", "com.jetbrains"]
        expect(settings.mode(forBundleID: "com.1password.1password") == .off, "менеджер паролей — выключено")
        expect(settings.mode(forBundleID: "com.apple.Terminal") == .manualOnly, "терминал — только вручную")
        expect(settings.mode(forBundleID: "com.jetbrains.intellij") == .manualOnly, "префикс покрывает семейство")
        expect(settings.mode(forBundleID: "com.jetbrainsX") == .auto, "префикс — только по границе точки")
        expect(settings.mode(forBundleID: "com.apple.Safari") == .auto, "остальные — авто")
        expect(settings.mode(forBundleID: nil) == .auto, "неизвестное приложение — авто")
    }

    suite("Снимок настроек для движка (гонки P0)") {
        let defaults = freshDefaults("com.smartswitcher.snapshot")
        let prefs = Preferences(defaults: defaults)
        prefs.neverCorrectWords = ["vim"]
        prefs.enabled = false
        expect(prefs.engine.neverCorrectWords == ["vim"], "снимок отражает изменения")
        expect(!prefs.engine.isActive(), "выключенный движок неактивен")
        prefs.enabled = true
        prefs.pausedUntil = Date().addingTimeInterval(60)
        expect(!prefs.engine.isActive(), "пауза делает движок неактивным")

        // Конкурентное чтение снимка во время записи не должно падать.
        let group = DispatchGroup()
        DispatchQueue.global().async(group: group) {
            for _ in 0..<20_000 { _ = prefs.engine.neverCorrectWords.contains("vim") }
        }
        for i in 0..<300 { prefs.neverCorrectWords.append("w\(i)") }
        group.wait()
        expect(prefs.engine.neverCorrectWords.count == 301, "снимок консистентен после конкурентной записи")
        defaults.removePersistentDomain(forName: "com.smartswitcher.snapshot")
    }

    suite("Автозамена — функция Pro (раздел 22)") {
        let defaults = freshDefaults("com.smartswitcher.pro")
        let prefs = Preferences(defaults: defaults)
        prefs.expansionRules = ["omw": "on my way"]
        let expander = TextExpander(preferences: prefs)
        expect(expander.expansion(for: "omw") == "on my way", "с Pro автозамена работает")
        prefs.proUnlocked = false
        expect(expander.expansion(for: "omw") == nil, "без Pro автозамена не срабатывает")
        defaults.removePersistentDomain(forName: "com.smartswitcher.pro")
    }

    suite("Лицензия: dev-сборка определяется по плейсхолдеру (P0)") {
        let placeholder = LicenseService(publicKeyBase64: LicenseService.placeholderPublicKeyBase64)
        expect(placeholder.isDevBuild, "плейсхолдер — dev-сборка, Pro открыт")
        let real = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        let release = LicenseService(publicKeyBase64: real)
        expect(!release.isDevBuild, "реальный ключ — не dev-сборка (раньше было всегда true)")
        expect(!release.proFeaturesUnlocked || release.isPro, "без лицензии Pro закрыт")
    }

    suite("Синхронизация: слияние правил слов (LWW)") {
        let local = WordRuleMerge.State(
            never: ["vim", "xcode"],
            always: [],
            added: ["never:vim": 10, "never:xcode": 20],
            removed: ["never:git": 30]
        )
        let remote = WordRuleMerge.State(
            never: ["vim", "git", "kubectl"],
            always: ["ghbdtn"],
            added: ["never:git": 5, "never:kubectl": 40, "always:ghbdtn": 50],
            removed: ["never:xcode": 25]
        )
        let merged = WordRuleMerge.merge(local: local, remote: remote)
        expect(merged.never.contains("vim"), "общее слово сохраняется")
        expect(merged.never.contains("kubectl"), "слово с другого Mac добавляется")
        expect(!merged.never.contains("git"), "удаление новее добавления — слово удалено")
        expect(!merged.never.contains("xcode"), "удаление с другого Mac применяется")
        expect(merged.always == ["ghbdtn"], "второй список сливается так же")
        let again = WordRuleMerge.merge(local: merged, remote: remote)
        expect(again == merged, "слияние идемпотентно")

        let legacy = WordRuleMerge.merge(
            local: .init(never: ["old"], always: [], added: [:], removed: [:]),
            remote: .init(never: [], always: [], added: [:], removed: ["never:old": 1])
        )
        expect(legacy.never.isEmpty, "удаление перекрывает слово без меток (до v3)")
    }

    suite("Метки правил слов в настройках") {
        let defaults = freshDefaults("com.smartswitcher.stamps")
        let prefs = Preferences(defaults: defaults)
        prefs.neverCorrectWords = ["vim"]
        expect(prefs.wordRuleAdded["never:vim"] != nil, "добавление помечено")
        prefs.neverCorrectWords = []
        expect(prefs.wordRuleRemoved["never:vim"] != nil, "удаление помечено")
        defaults.removePersistentDomain(forName: "com.smartswitcher.stamps")
    }

    suite("Импорт v3 в режиме слияния не трогает «включено»") {
        let defaults = freshDefaults("com.smartswitcher.merge")
        let prefs = Preferences(defaults: defaults)
        let service = ImportExportService(preferences: prefs)
        prefs.enabled = false
        prefs.neverCorrectWords = ["local"]
        let now = Int(Date().timeIntervalSince1970)
        let json = """
        {"version": 3, "enabled": true, "soundEnabled": true, "excludedApps": [],
         "neverCorrectWords": ["remote"], "alwaysCorrectWords": [],
         "manualOnlyApps": ["com.apple.Terminal"],
         "wordRuleAdded": {"never:remote": \(now)}, "wordRuleRemoved": {}}
        """
        let data = Data(json.utf8)
        try? service.importData(data, mode: .merge)
        expect(!prefs.enabled, "флаг «включено» локален для Mac")
        expect(Set(prefs.neverCorrectWords) == ["local", "remote"], "списки слов объединены")
        expect(prefs.manualOnlyApps == ["com.apple.Terminal"], "режимы приложений применены")
        try? service.importData(data, mode: .replace)
        expect(prefs.enabled, "импорт файла заменяет и «включено»")
        defaults.removePersistentDomain(forName: "com.smartswitcher.merge")
    }

    suite("Обновления: сравнение версий") {
        expect(UpdateService.isNewer("0.4.0", than: "0.3.0"), "0.4.0 > 0.3.0")
        expect(UpdateService.isNewer("v1.10.0", than: "1.9.9"), "v1.10.0 > 1.9.9 (числовое сравнение)")
        expect(!UpdateService.isNewer("0.3.0", than: "0.3.0"), "равные версии")
        expect(!UpdateService.isNewer("0.3", than: "0.3.0"), "0.3 == 0.3.0")
        let configured = MainActor.assumeIsolated {
            UpdateService(preferences: Preferences(defaults: freshDefaults("com.smartswitcher.upd"))).isConfigured
        }
        expect(!configured, "без SSGitHubRepository проверка выключена")
    }

    suite("Статистика: только счётчики") {
        let defaults = freshDefaults("com.smartswitcher.stats")
        let stats = StatisticsService(defaults: defaults)
        stats.record(.auto, savedKeystrokes: 10)
        stats.record(.auto, savedKeystrokes: 6)
        stats.record(.manual)
        expect(stats.day().count(.auto) == 2, "два авто-исправления сегодня")
        expect(stats.total.savedKeystrokes == 16, "сэкономленные нажатия суммируются")
        let reloaded = StatisticsService(defaults: defaults)
        expect(reloaded.total.count(.manual) == 1, "статистика переживает перезапуск")
        expect(stats.lastDays(14).count == 14, "график за 14 дней")
        stats.reset()
        expect(stats.total.count(.auto) == 0, "сброс статистики")
        defaults.removePersistentDomain(forName: "com.smartswitcher.stats")
    }

    suite("Выделение: раскладка, регистр, транслит") {
        let converter = StaticLayoutConverter()
        let layout = SelectionConverter.convertLayout("ghbdtn vbh, 2024!", converter: converter)
        expect(layout?.text == "привет мирб 2024!", "конвертация фразы; цифры и пробелы не трогаются")
        expect(layout?.target == .ru, "целевая раскладка RU")
        expect(SelectionConverter.convertLayout("руддщ", converter: converter)?.text == "hello", "RU → EN")
        expect(SelectionConverter.convertLayout("2024", converter: converter) == nil, "без букв — нечего конвертировать")
        expect(SelectionConverter.invertCase("пРИВЕТ, wORLD") == "Привет, World", "инверсия регистра (Caps Lock)")
        expect(SelectionConverter.transliterate("Щука и ёж") == "Shchuka i yozh", "кириллица → латиница")
        expect(SelectionConverter.transliterate("Privet, shchuka") == "Привет, щука", "латиница → кириллица")
    }

    suite("InputGate: ввод придерживается на время перенабора") {
        var replayed: [Int64] = []
        let gate = InputGate { events in
            replayed += events.map { $0.getIntegerValueField(.keyboardEventKeycode) }
        }
        func key(_ code: CGKeyCode) -> CGEvent {
            CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!
        }
        expect(!gate.capture(key(2)), "выключенный gate ничего не держит (listen-only)")
        gate.isEnabled = true
        expect(!gate.capture(key(2)), "без удержания события проходят")
        gate.hold()
        gate.hold()
        expect(gate.capture(key(2)) && gate.capture(key(3)), "во время перенабора нажатия придержаны")
        gate.release()
        expect(replayed.isEmpty, "вложенное удержание ещё не отпускает")
        gate.release()
        expect(replayed == [2, 3], "после перенабора нажатия воспроизведены по порядку")
        gate.release()
        expect(replayed == [2, 3], "лишний release безопасен")
    }

    suite("Системные раскладки: таблицы UCKeyTranslate") {
        let controller = LayoutController()
        let sources = controller.sourcesForConversion()
        guard sources[.en] != nil, sources[.ru] != nil else {
            print("    (пропуск: в системе не включены обе раскладки EN и RU)")
            return
        }
        let system = SystemLayoutConverter()
        system.rebuild(sources: sources)
        expect(system.convert("ghbdtn", from: .en, to: .ru) == "привет", "буквы EN → RU по реальной раскладке")
        expect(system.convert("руддщ", from: .ru, to: .en) == "hello", "буквы RU → EN по реальной раскладке")
        expect(system.convert("Ghbdtn", from: .en, to: .ru) == "Привет", "регистр через Shift-слой")
        expect(system.isMappable("ж") && system.isMappable("q"), "буквы маппируются")
    }
}
