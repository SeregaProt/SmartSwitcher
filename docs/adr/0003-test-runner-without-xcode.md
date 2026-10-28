# ADR-0003: Собственный тест-раннер вместо XCTest

Дата: 2026-06-13. Статус: принято (временно, до полного Xcode).

## Контекст
Среда разработки — только Command Line Tools: модули `XCTest` и `Testing`
недоступны (`swift test` падает с «no such module 'Testing'»).

## Решение
Исполняемая цель `SmartSwitcherChecks` (Tests/SmartSwitcherChecks) с минимальным
раннером (`suite`/`expect`, ненулевой exit-код при провале). Запуск:
`make test` → `swift run SmartSwitcherChecks`.

## Последствия
- (+) Тесты и метрики качества работают в любой среде, включая CI.
- (+) API раннера повторяет дух swift-testing — миграция на `#expect`
  механическая, когда появится полный Xcode.
- (−) Нет параллелизма, фильтрации и отчётов XCTest. Приемлемо: набор
  выполняется секунды.
