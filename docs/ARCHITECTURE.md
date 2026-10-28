# Архитектура SmartSwitcher

Обзор для разработчиков. Детальные решения — в [ADR](adr/).

## Принципы

1. **Детектор — заменяемый «мозг»** за протоколом `LanguageDetector`. Качество
   продукта растёт заменой/обучением детектора, не переписыванием ядра.
2. **Перехват отделён от решений**: `EventTapManager` только декодирует события,
   вся логика — в `SwitcherEngine`.
3. **Precision над recall**: при сомнении ввод не трогаем (ТЗ 7.2).
4. **Privacy by design**: текст живёт только в памяти; логи — без текста.

## Модули

```
Sources/SmartSwitcherKit/
├── App/
│   └── AppDelegate          сборка модулей, онбординг, конфликт-детект, хоткеи
├── Core/
│   ├── EventTapManager      CGEventTap: listen-only или активный (ADR-0008)
│   ├── InputGate            придерживание ввода на время перенабора
│   ├── InputBuffer          буфер слова (все символы), таинт, lastCommitted
│   ├── SwitcherEngine       поток данных: событие→буфер→детект→правила→замена
│   ├── LayoutController     TIS: смена раскладки, предпочитаемый source языка
│   ├── TextReplacer         Backspace + посимвольная unicode-вставка с маркером
│   ├── HotKeyCenter         Carbon RegisterEventHotKey (⌃⌥K/U/T)
│   └── Layout               enum раскладок (en/ru, расширяемо)
├── Brain/                   ЗАМЕНЯЕМЫЙ МОДУЛЬ
│   ├── LanguageDetector     протокол + Verdict + DetectionContext
│   ├── StatisticalDetector  словари + триграммная модель + контекст фразы
│   ├── NGramModel           P(c|ab)·0,7 + P(c|b)·0,3, маркеры ^^слово$
│   ├── LayoutConverter      таблицы по реальным раскладкам (UCKeyTranslate)
│   ├── LayoutMapping        статическая таблица US↔«Русская – ПК» (фолбэк)
│   ├── PersonalDictionary   личный словарь: солёные хеши, 3 подтверждения
│   ├── DictionaryService    top-9000 слов на язык, ленивая загрузка
│   ├── StopRules            числа/URL/пути/идентификаторы → не трогать
│   └── LanguageData         встроенный мини-словарь (fallback)
├── Rules/
│   ├── AppRulesManager      режимы приложений: авто / вручную / выключено
│   └── WordRulesManager     never/always списки + нормализация
├── Services/
│   ├── ShiftGestureDetector жесты Shift (single/double, чистая логика)
│   ├── SelectionConverter   выделение: раскладка, регистр, транслит
│   ├── StatisticsService    счётчики по дням (без слов)
│   ├── DiaryService         дневник: AES-GCM, ключ в Keychain, выкл по умолч.
│   ├── ImportExportService  JSON-снапшот v3 + WordRuleMerge (LWW-element-set)
│   ├── SyncService          iCloud KVS, слияние списков слов (ADR-0007)
│   ├── LicenseService       Ed25519-ключи, Pro: синхронизация, автозамена
│   ├── UpdateService        проверка версии через GitHub Releases
│   ├── TextExpander         автозамена (Pro)
│   ├── ConflictDetector     CGGetEventTapList: чужие активные тапы
│   ├── NotificationService  уведомления без текста
│   └── LocalizationService  L10n поверх NSLocalizedString(bundle: .module)
├── UI/
│   ├── MenuBarController    NSStatusItem, индикатор раскладки, пауза, обновления
│   ├── CorrectionHUD        плашка раскладки у каретки
│   ├── SettingsWindow       SwiftUI с боковой навигацией (11 разделов)
│   └── OnboardingWindow     мастер первого запуска
├── Infrastructure/
│   ├── Preferences          @Published + потокобезопасный снимок EngineSettings
│   ├── KeychainHelper       generic password create/read/delete
│   ├── Logger               os.log; НИКОГДА не пишет набранный текст
│   ├── CrashGuard           async-signal-safe обработчик сигналов
│   └── PermissionsManager   AXIsProcessTrusted + FocusInspector (secure input)
└── Resources/
    ├── {ru,en}_words.txt    словари (см. docs/DICTIONARIES.md)
    ├── {ru,en}_ngrams.tsv   символьные модели
    └── {ru,en}.lproj/       локализация UI
```

## Поток данных

```
keyDown (поток tap; в надёжном режиме — через InputGate)
 → SwitcherEngine.handle → серийная очередь
   → Cmd/Ctrl/Opt, клик, стрелки, Esc, смена приложения → сброс контекста
     (буфер + последнее слово: Double-Shift не тронет текст в новом месте)
   → Backspace → откат исправления (opt-in) или буфер.backspace
     (стёрт пробел — снова редактируем прошлое слово)
   → Enter/Tab → commit без исправления и без запоминания (ADR-0005);
     в надёжном режиме Enter придерживается и слово исправляется (ADR-0008)
   → разделитель (пробел, !()%*+=)
      → буфер.commit → токен
      → активен? режим приложения «авто»? не secure input?
      → автозамена (Pro) → иначе neverCorrect / alwaysCorrect
      → детектор.analyze(токен, контекст фразы + Caps Lock)
      → correct? → LayoutController.select (сначала раскладка)
                 → TextReplacer.replace (gate держит ввод)
                 → статистика, дневник, HUD/звук/уведомление
      → keep? → кандидат в личный словарь (подтверждается следующим словом)
```

Double-Shift → принудительная конвертация текущего/последнего слова (работает
и в режиме «только вручную»); откат свежего авто-исправления отправляет слово
в исключения (самообучение), ручная правка сжигает подтверждения личного словаря.

## Потоки и производительность

- Event tap — выделенный поток с runloop, QoS userInteractive.
- Состояние движка — только на его серийной очереди; настройки движок читает
  из снимка `Preferences.engine` под блокировкой (никаких гонок с UI).
- Библиотека собирается в Swift 6 language mode (строгая проверка
  параллелизма): UI на `@MainActor`, потокобезопасные классы помечены
  `@unchecked Sendable` с описанием инварианта.
- Accessibility-запросы — с таймаутом 0,15 с: зависшее приложение не
  останавливает движок.
- Анализ слова ~0,008 мс (бенчмарк в Checks), бюджет ТЗ — 5 мс.

## Тестирование

- `make test` → `SmartSwitcherChecks` (272 проверки): маппинг, буфер, жесты,
  детектор с контекстом и Caps Lock, личный словарь, метрики на словарных и
  отложенных словах (регрессионный gate), бенчмарк, слияние синхронизации,
  лицензия, обновления, статистика, InputGate, системные раскладки.
- `make integration` → настоящий `SwitcherEngine` печатает в своё окно:
  12 сценариев, включая регрессии P0 (Double-Shift после клика и Enter),
  контекст, Caps Lock, исправление перед Enter, паузу.
