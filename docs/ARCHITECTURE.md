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
│   └── AppDelegate          сборка модулей, онбординг, конфликт-детект
├── Core/
│   ├── EventTapManager      CGEventTap (listen-only), свой поток+runloop
│   ├── InputBuffer          буфер слова, таинт, lastCommitted
│   ├── SwitcherEngine       поток данных: событие→буфер→детект→правила→замена
│   ├── LayoutController     TIS: чтение/смена input source, кэш
│   ├── TextReplacer         Backspace-эмуляция + unicode-вставка с маркером
│   └── Layout               enum раскладок (en/ru, расширяемо)
├── Brain/                   ЗАМЕНЯЕМЫЙ МОДУЛЬ
│   ├── LanguageDetector     протокол + Verdict (keep/correct)
│   ├── StatisticalDetector  основной: словари + биграммные модели
│   ├── HeuristicDetector    резервный: эвристики без ресурсов
│   ├── NGramModel           log10 P(биграмма) с маркерами ^слово$
│   ├── DictionaryService    top-9000 слов на язык, ленивая загрузка
│   ├── LayoutMapping        QWERTY↔ЙЦУКЕН посимвольно (вкл. пунктуацию)
│   ├── StopRules            числа/URL/пути/идентификаторы → не трогать
│   └── LanguageData         встроенный мини-словарь (fallback)
├── Rules/
│   ├── AppExclusionManager  белый список приложений
│   └── WordRulesManager     never/always списки + нормализация
├── Services/
│   ├── DoubleShiftDetector  жест Shift-Shift (чистая логика)
│   ├── DiaryService         дневник: AES-GCM, ключ в Keychain, выкл по умолч.
│   ├── ImportExportService  JSON-снапшот настроек, валидация
│   ├── ConflictDetector     CGGetEventTapList: чужие активные тапы
│   ├── LocalizationService  L10n поверх NSLocalizedString(bundle: .module)
│   └── UpdateService        заглушка до Sparkle (ADR-0006)
├── UI/
│   ├── MenuBarController    NSStatusItem, индикатор раскладки, пауза
│   └── SettingsWindow       SwiftUI: Общие/Исключения/Слова/Дневник/Приватность
├── Infrastructure/
│   ├── Preferences          ObservableObject поверх UserDefaults, миграции
│   ├── KeychainHelper       generic password create/read/delete
│   ├── Logger               os.log; НИКОГДА не пишет набранный текст
│   └── PermissionsManager   AXIsProcessTrusted + FocusInspector (secure field)
└── Resources/
    ├── {ru,en}_words.txt    словари (см. docs/DICTIONARIES.md)
    ├── {ru,en}_bigrams.tsv  биграммные модели
    └── {ru,en}.lproj/       локализация UI
```

## Поток данных

```
keyDown (поток tap)
 → SwitcherEngine.handle
   → Cmd/Ctrl/Opt? → reset буфера
   → Backspace? → буфер.backspace
   → Enter/Tab? → commit без исправления (ADR-0005)
   → буферизуемый символ? → буфер.append
   → разделитель (пробел, !()%*+=)?
      → буфер.commit → токен
      → активен? приложение не исключено? не secure field?
      → не в neverCorrect? (always → принудительная конвертация)
      → детектор.analyze:
         стоп-листы → словарь источника → конвертация → словарь цели
         → биграммный перевес → Verdict
      → correct? → TextReplacer.replace (backspace×N + unicode-чанки)
                 → LayoutController.select
                 → дневник (если включён), звук, иконка
```

Double-Shift (flagsChanged) → принудительная конвертация текущего/последнего
слова; если это откат свежего авто-исправления — слово уходит в исключения
(самообучение).

## Потоки и производительность

- Event tap живёт на выделенном потоке с runloop, QoS userInteractive.
- Анализ слова выполняется только на границе слова: ~0,01 мс на слово
  (бенчмарк в Checks), бюджет ТЗ — 5 мс.
- Ресурсы детектора грузятся лениво + прогрев в фоне при старте.
- UI-операции диспатчатся на main.

## Тестирование

`make test` → `swift run SmartSwitcherChecks` (без Xcode нет XCTest, ADR-0003):
маппинг, буфер, жест, оба детектора, метрики качества на корпусе 12k слов
(recall/false-positives — регрессионный gate, ТЗ 16), бенчмарк латентности,
импорт/экспорт.
