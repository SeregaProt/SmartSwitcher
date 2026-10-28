# SBOM — состав программного обеспечения SmartSwitcher

Учёт компонентов (ТЗ 25). Версия 0.3.0, 2026-06-13.

## Прямые зависимости (код)

| Компонент | Версия | Лицензия | Назначение |
|---|---|---|---|
| (нет сторонних SPM-пакетов) | — | — | Ядро использует только системные фреймворки macOS |

Планируется в релизной фазе:

| Компонент | Версия | Лицензия | Назначение |
|---|---|---|---|
| Sparkle | 2.x | MIT | Авто-обновления вне App Store (ADR-0006) |

## Системные фреймворки Apple

AppKit, SwiftUI, Combine, Carbon/HIToolbox, CoreGraphics, ApplicationServices,
CryptoKit, Security, ServiceManagement, UserNotifications, os.log — поставляются
с macOS, отдельного лицензирования не требуют.

## Данные (ресурсы)

| Ресурс | Источник | Лицензия |
|---|---|---|
| `{ru,en}_words.txt`, `{ru,en}_bigrams.tsv`, оценочные фикстуры | hermitdave/FrequencyWords (OpenSubtitles 2018) | CC-BY-SA 4.0 |

Подробности и атрибуция — в [NOTICE](NOTICE).

## Инструменты сборки и разработки

| Инструмент | Лицензия | Назначение |
|---|---|---|
| Swift / SwiftPM | Apache-2.0 | Компиляция и сборка |
| SwiftLint | MIT | Линт (CI) |

## Код приложения

Ядро SmartSwitcher — лицензия [MIT](LICENSE). Коммерческие модули (план Pro) —
проприетарны (open-core, ТЗ 22/25).
