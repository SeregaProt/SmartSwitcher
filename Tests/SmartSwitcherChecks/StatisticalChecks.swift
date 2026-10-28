import CryptoKit
import Foundation
import SmartSwitcherKit

/// Проверки фазы 2: статистический детектор, метрики качества (ТЗ 7.2),
/// производительность (ТЗ 8), импорт/экспорт.
func runPhase2Checks() {
    let dictionaries = DictionaryService()
    let ngrams = NGramModel()
    dictionaries.warmUp()
    ngrams.warmUp()
    let detector = StatisticalDetector(dictionaries: dictionaries, ngrams: ngrams)

    suite("Ресурсы: словари и модели загружаются") {
        expect(dictionaries.words(for: .ru).count > 5000, "русский словарь загружен")
        expect(dictionaries.words(for: .en).count > 5000, "английский словарь загружен")
        expect(ngrams.score("привет", in: .ru) != nil, "RU биграммы работают")
        expect(ngrams.score("hello", in: .en) != nil, "EN биграммы работают")
        expect(
            (ngrams.score("привет", in: .ru) ?? -99) > (ngrams.score("ghbdtn", in: .en) ?? 0),
            "слово правдоподобнее мусора"
        )
    }

    suite("Статистический детектор: золотой корпус исправлений") {
        let corrections: [(String, String, Layout)] = [
            ("ghbdtn", "привет", .ru),
            ("ckjdj", "слово", .ru),
            ("rfr", "как", .ru),
            ("ltkf", "дела", .ru),
            ("xnj", "что", .ru),
            ("cgfcb,j", "спасибо", .ru),
            ("vjcrdf", "москва", .ru),
            ("[jhjij", "хорошо", .ru),
            ("ctujlyz", "сегодня", .ru),
            ("hf,jnf", "работа", .ru),
            ("Ghbdtn", "Привет", .ru),
            ("ghbdtn?", "привет,", .ru),
            ("руддщ", "hello", .en),
            ("еру", "the", .en),
            ("цщкв", "word", .en),
            ("руддщб", "hello,", .en),
        ]
        for (input, expected, layout) in corrections {
            expect(
                detector.analyze(input) == .correct(layout: layout, replacement: expected),
                "\(input) → \(expected), получено: \(detector.analyze(input))"
            )
        }
    }

    suite("Статистический детектор: валидные слова и стоп-листы") {
        let keeps = [
            "hello", "the", "world", "swift", "don't", "qwerty", "really",
            "привет", "спасибо", "мама", "работа", "Привет", "файл", "программа",
            "test123", "user@mail.com", "example.com", "/usr/local", "--force",
            "snake_case", "camelCase", "HTML", "GHBDTN",
        ]
        for word in keeps {
            expect(detector.analyze(word) == .keep, "не трогать: \(word), получено: \(detector.analyze(word))")
        }
    }

    // MARK: - Метрики качества (ТЗ 7.2): precision > 98%, recall > 90%

    func fixture(_ name: String) -> [String] {
        guard let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "txt"),
              let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return content.split(separator: "\n").map(String.init)
    }

    suite("Метрики качества детектора (ТЗ 7.2)") {
        let ruTop = fixture("eval_ru_top")
        let enTop = fixture("eval_en_top")
        let ruRare = fixture("eval_ru_rare")
        let enRare = fixture("eval_en_rare")
        expect(ruTop.count == 3000 && enRare.count == 3000, "фикстуры загружены")

        // Recall: русские слова, «набранные» в EN-раскладке, должны ловиться.
        var caught = 0, total = 0
        for word in ruTop {
            guard let garbage = LayoutMapping.toEnglish(word) else { continue }
            total += 1
            if case .correct(.ru, let fixed) = detector.analyze(garbage), fixed == word {
                caught += 1
            }
        }
        let recall = Double(caught) / Double(total)
        print("    recall (RU-мусор в EN): \(String(format: "%.1f%%", recall * 100)) (\(caught)/\(total))")
        expect(recall > 0.90, "recall > 90%, фактически \(String(format: "%.1f%%", recall * 100))")

        // Recall в обратную сторону: английский в RU-раскладке.
        var caughtEn = 0, totalEn = 0
        for word in enTop {
            guard let garbage = LayoutMapping.toRussian(word) else { continue }
            totalEn += 1
            if case .correct(.en, let fixed) = detector.analyze(garbage), fixed == word {
                caughtEn += 1
            }
        }
        let recallEn = Double(caughtEn) / Double(totalEn)
        print("    recall (EN-мусор в RU): \(String(format: "%.1f%%", recallEn * 100)) (\(caughtEn)/\(totalEn))")
        expect(recallEn > 0.90, "recall EN > 90%, фактически \(String(format: "%.1f%%", recallEn * 100))")

        // Precision-стресс: валидные, но РЕДКИЕ слова (вне словаря) не должны
        // исправляться. Ложное срабатывание — главный грех (ТЗ 1.3, 7.2).
        var falsePositives = 0
        for word in enRare + ruRare {
            if case .correct = detector.analyze(word) {
                falsePositives += 1
            }
        }
        let fpRate = Double(falsePositives) / Double(enRare.count + ruRare.count)
        print("    ложные срабатывания на редких словах: \(String(format: "%.2f%%", fpRate * 100)) (\(falsePositives)/\(enRare.count + ruRare.count))")
        expect(fpRate < 0.02, "ложных срабатываний < 2% на словах вне словаря, фактически \(String(format: "%.2f%%", fpRate * 100))")

        // Честная оценка (docs/DICTIONARIES.md): отложенная выборка — слова,
        // которых нет ни в словаре, ни в обучении модели.
        let ruOOV = fixture("eval_ru_oov")
        let enOOV = fixture("eval_en_oov")
        expect(ruOOV.count == 3000 && enOOV.count == 3000, "OOV-фикстуры загружены")
        func oovRecall(_ words: [String], to layout: Layout, context: DetectionContext) -> Double {
            var hit = 0, all = 0
            for word in words {
                let garbage = layout == .ru ? LayoutMapping.toEnglish(word) : LayoutMapping.toRussian(word)
                guard let garbage else { continue }
                all += 1
                if detector.analyze(garbage, context: context) == .correct(layout: layout, replacement: word) { hit += 1 }
            }
            return Double(hit) / Double(max(all, 1))
        }
        func oovFalsePositives(_ words: [String], context: DetectionContext) -> Double {
            Double(words.filter { detector.analyze($0, context: context) != .keep }.count) / Double(words.count)
        }
        let pct: (Double) -> String = { String(format: "%.1f%%", $0 * 100) }
        let recallRuOOV = oovRecall(ruOOV, to: .ru, context: .none)
        let recallEnOOV = oovRecall(enOOV, to: .en, context: .none)
        let recallRuCtx = oovRecall(ruOOV, to: .ru, context: DetectionContext(previousLanguage: .ru))
        let recallEnCtx = oovRecall(enOOV, to: .en, context: DetectionContext(previousLanguage: .en))
        print("    recall вне словаря: RU \(pct(recallRuOOV)), EN \(pct(recallEnOOV)); в контексте фразы: RU \(pct(recallRuCtx)), EN \(pct(recallEnCtx))")
        expect(recallRuOOV > 0.85, "recall RU вне словаря > 85%, фактически \(pct(recallRuOOV))")
        expect(recallEnOOV > 0.78, "recall EN вне словаря > 78%, фактически \(pct(recallEnOOV))")
        expect(recallRuCtx >= recallRuOOV && recallEnCtx >= recallEnOOV, "контекст не ухудшает recall")

        let fpRu = oovFalsePositives(ruOOV, context: .none)
        let fpEn = oovFalsePositives(enOOV, context: .none)
        // Худший случай: слово чужого языка посреди фразы на языке кандидата.
        let fpRuCtx = oovFalsePositives(ruOOV, context: DetectionContext(previousLanguage: .en))
        let fpEnCtx = oovFalsePositives(enOOV, context: DetectionContext(previousLanguage: .ru))
        print("    ложные срабатывания вне словаря: RU \(String(format: "%.2f%%", fpRu * 100)), EN \(String(format: "%.2f%%", fpEn * 100)); худший контекст: RU \(String(format: "%.2f%%", fpRuCtx * 100)), EN \(String(format: "%.2f%%", fpEnCtx * 100))")
        expect(max(fpRu, fpEn) < 0.005, "ложных срабатываний вне словаря < 0.5%")
        expect(max(fpRuCtx, fpEnCtx) < 0.006, "ложных срабатываний в худшем контексте < 0.6%")

        // На частотных (словарных) словах ложных срабатываний быть не должно вовсе.
        var dictFP = 0
        for word in (ruTop.prefix(2000) + enTop.prefix(2000)) {
            if case .correct = detector.analyze(word) { dictFP += 1 }
        }
        print("    ложные срабатывания на частотных словах: \(dictFP)")
        expect(dictFP == 0, "0 ложных срабатываний на частотных словах, фактически \(dictFP)")
    }

    // MARK: - Производительность (ТЗ 8, NFR: < 5 мс на слово)

    suite("Производительность детектора") {
        let samples = (fixture("eval_ru_top").prefix(500).compactMap { LayoutMapping.toEnglish($0) }
            + fixture("eval_en_top").prefix(500).map { $0 })
        let start = DispatchTime.now()
        var corrections = 0
        for word in samples {
            if case .correct = detector.analyze(word) { corrections += 1 }
        }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e6
        let perWord = elapsed / Double(samples.count)
        print("    среднее время анализа слова: \(String(format: "%.3f", perWord)) мс")
        expect(perWord < 5.0, "анализ слова < 5 мс, фактически \(String(format: "%.3f", perWord)) мс")
        expect(corrections > 0, "бенчмарк не выродился")
    }

    // MARK: - Импорт/экспорт (раздел 24)

    suite("Импорт/экспорт конфигурации") {
        let defaults = UserDefaults(suiteName: "com.smartswitcher.checks")!
        defaults.removePersistentDomain(forName: "com.smartswitcher.checks")
        let prefs = Preferences(defaults: defaults)
        prefs.neverCorrectWords = ["xcode", "vim"]
        prefs.alwaysCorrectWords = ["ghbdtn"]
        prefs.soundEnabled = false
        let service = ImportExportService(preferences: prefs)

        guard let data = try? service.exportData() else {
            expect(false, "экспорт не упал")
            return
        }
        expect(data.count > 50, "экспорт непустой")

        guard let snapshot = try? JSONDecoder().decode(ImportExportService.Snapshot.self, from: data) else {
            expect(false, "экспорт — валидный JSON схемы Snapshot")
            return
        }
        expect(snapshot.neverCorrectWords == ["xcode", "vim"], "слова never в снапшоте")
        expect(snapshot.alwaysCorrectWords == ["ghbdtn"], "слова always в снапшоте")
        expect(snapshot.soundEnabled == false, "звук в снапшоте")

        expect((try? service.importData(data)) != nil, "импорт валидного файла проходит")
        expect((try? service.importData(Data("мусор".utf8))) == nil, "импорт мусора отклоняется")
        defaults.removePersistentDomain(forName: "com.smartswitcher.checks")
    }

    suite("Лицензирование: офлайн-проверка ключа (FR-22)") {
        // Генерируем издательскую пару ключей; подписываем лицензию приватным,
        // проверяем публичным — полный реальный цикл активации.
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicB64 = privateKey.publicKey.rawRepresentation.base64EncodedString()

        func makeKey(email: String, plan: String, expiry: TimeInterval) -> String {
            let payload = "{\"email\":\"\(email)\",\"plan\":\"\(plan)\",\"expiry\":\(Int(expiry))}"
            let payloadData = Data(payload.utf8)
            let sig = try! privateKey.signature(for: payloadData)
            return LicenseService.base64urlEncode(payloadData) + "." + LicenseService.base64urlEncode(sig)
        }

        // Изолированный аккаунт Keychain для теста чистится деактивацией.
        let service = LicenseService(publicKeyBase64: publicB64)
        service.deactivate()
        expect(!service.isPro, "по умолчанию — бесплатный план")

        let validKey = makeKey(email: "user@example.com", plan: "pro", expiry: 0)
        let activated = try? service.activate(key: validKey)
        expect(activated != nil, "валидный ключ активируется")
        expect(activated?.email == "user@example.com", "email из ключа")
        expect(activated?.plan == .pro, "план Pro")

        // Подделка подписи: payload от другого ключа.
        let attacker = Curve25519.Signing.PrivateKey()
        let payload = Data("{\"email\":\"x\",\"plan\":\"pro\",\"expiry\":0}".utf8)
        let fakeSig = try! attacker.signature(for: payload)
        let fakeKey = LicenseService.base64urlEncode(payload) + "." + LicenseService.base64urlEncode(fakeSig)
        var rejected = false
        do { _ = try service.activate(key: fakeKey) } catch { rejected = true }
        expect(rejected, "ключ с чужой подписью отклоняется")

        // Просроченный ключ.
        let expiredKey = makeKey(email: "old@example.com", plan: "pro", expiry: 1000)
        var expiredRejected = false
        do { _ = try service.activate(key: expiredKey) } catch LicenseService.ActivationError.expired { expiredRejected = true } catch {}
        expect(expiredRejected, "просроченный ключ отклоняется")

        // Мусор.
        var malformed = false
        do { _ = try service.activate(key: "не-ключ") } catch { malformed = true }
        expect(malformed, "мусорный ключ отклоняется")

        service.deactivate()
    }

    suite("Нормализация правил слов") {
        expect(WordRulesManager.normalize("«Привет!»") == "привет", "обрезка пунктуации и регистра")
        expect(WordRulesManager.normalize("  ") == "", "пустое слово")
    }

    suite("Автозамена текста (FR-7)") {
        let defaults = UserDefaults(suiteName: "com.smartswitcher.expansion")!
        defaults.removePersistentDomain(forName: "com.smartswitcher.expansion")
        let prefs = Preferences(defaults: defaults)
        prefs.expansionRules = ["omw": "on my way", "адр": "ул. Пушкина, д. 1"]
        let expander = TextExpander(preferences: prefs)

        expect(expander.expansion(for: "omw") == "on my way", "базовое разворачивание")
        expect(expander.expansion(for: "Omw") == "On my way", "сохранение Заглавной")
        expect(expander.expansion(for: "OMW") == "ON MY WAY", "сохранение КАПСА")
        expect(expander.expansion(for: "omw,") == "on my way", "пунктуация по краям игнорируется")
        expect(expander.expansion(for: "адр") == "ул. Пушкина, д. 1", "кириллическое правило")
        expect(expander.expansion(for: "hello") == nil, "нет правила — nil")

        prefs.textExpansionEnabled = false
        expect(expander.expansion(for: "omw") == nil, "выключенная автозамена не срабатывает")
        defaults.removePersistentDomain(forName: "com.smartswitcher.expansion")
    }

    suite("Жесты Shift: single и double (FR-4)") {
        let shift = ShiftGestureDetector.leftShiftKeyCode
        func tap(_ d: ShiftGestureDetector, down: Double, up: Double) -> ShiftGesture {
            _ = d.handleFlagsChanged(keyCode: shift, flags: .maskShift, time: down)
            return d.handleFlagsChanged(keyCode: shift, flags: [], time: up)
        }

        let d1 = ShiftGestureDetector(window: 0.4)
        expect(tap(d1, down: 0.0, up: 0.1) == .none, "первое нажатие — не жест сразу")
        expect(tap(d1, down: 0.2, up: 0.3) == .double, "второе быстрое — double")

        let d2 = ShiftGestureDetector(window: 0.4)
        expect(tap(d2, down: 0.0, up: 0.1) == .none, "одиночное нажатие — не double")
        expect(d2.pendingSingle(now: 0.6) == .single, "после окна без второго — single")
        expect(d2.pendingSingle(now: 0.7) == .none, "single эмитится один раз")

        let d3 = ShiftGestureDetector(window: 0.4)
        _ = tap(d3, down: 0.0, up: 0.1)
        d3.noteKeyDown()
        expect(d3.pendingSingle(now: 0.6) == .none, "клавиша между сбрасывает single")
    }

    suite("Языки детекта: гейтинг по активным раскладкам") {
        // Только EN активен → русский мусор в EN не исправляется (target RU выключен).
        let onlyEn = StatisticalDetector(
            dictionaries: dictionaries, ngrams: ngrams,
            enabledLayouts: { [.en] }
        )
        expect(onlyEn.analyze("ghbdtn") == .keep, "RU выключен → ghbdtn не трогается")
        // EN-мусор в RU всё ещё чинится (target EN активен).
        if case .correct(.en, _) = onlyEn.analyze("руддщ") {
            expect(true, "EN активен → руддщ → hello")
        } else {
            expect(false, "ожидалось исправление в EN")
        }
    }

    // Регрессия краша 2026-06-13: TIS-вызовы с фонового потока роняли процесс
    // (dispatch_assert_queue в HIToolbox). LayoutController должен маршалить
    // смену раскладки на главный поток и не падать при вызове из любого потока.
    suite("LayoutController потокобезопасен (регрессия краша)") {
        let controller = LayoutController()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInteractive).async {
            // Эти вызовы раньше вызывали SIGTRAP на фоновом потоке.
            _ = controller.current()
            controller.select(.ru)
            controller.select(.en)
            _ = controller.current()
            done.signal()
        }
        let timedOut = done.wait(timeout: .now() + 3) == .timedOut
        expect(!timedOut, "вызовы LayoutController с фонового потока завершились без краша")
    }
}
