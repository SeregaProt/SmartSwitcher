# Формат словарей и моделей детектора

Документация по данным «мозга» (ТЗ 6.2). Все файлы лежат в
`Sources/SmartSwitcherKit/Resources/` и регенерируются скриптом
`Tools/generate_language_data.py` (источник — см. NOTICE и ADR-0004).

## Словари слов: `{ru,en}_words.txt`

- Одно слово в строке, нижний регистр, NFC.
- Отсортированы по убыванию частоты, top-9000 на язык.
- Фильтр: только буквы соответствующего алфавита (`[а-яё]+` / `[a-z']+`),
  без цифр и дефисов.
- Загружаются в `Set<String>` (DictionaryService), ленивая инициализация.

## Биграммные модели: `{ru,en}_bigrams.tsv`

- Строка: `биграмма<TAB>log10_вероятность`.
- Биграммы считаются по словам с маркерами границ: слово `кот` даёт
  `^к`, `ко`, `от`, `т$`. Маркеры позволяют модели учитывать характерные
  начала/окончания слов.
- Частоты взвешены корпусной частотой слова; вероятность —
  `count(биграмма) / суммарное число биграмм корпуса`.
- Невиданная биграмма получает floor `-6.5` (NGramModel.floorLogP).

## Оценка слова

`NGramModel.score(word, layout)` = средний log10 P по биграммам `^word$`
(только буквы, lowercased). Типичные значения: частое слово ≈ −1,8…−2,6;
мусор чужой раскладки ≈ −4…−6.

## Решающее правило (StatisticalDetector)

1. Стоп-листы (`StopRules`) → keep.
2. Ядро токена в словаре языка набора → keep.
3. Конвертация в словаре другого языка и `score(цель) > score(источник)` → correct.
4. Вне словарей: `score(источник) < −3.2` И `score(цель) > −2.6` И разрыв
   `> 1.2` → correct; иначе keep.

Пороги подобраны по оценочному стенду (Tests/SmartSwitcherChecks):
recall 96–99%, ложные срабатывания 0,05% на словах вне словаря, 0 — на
частотных. Регрессионный стенд — обязательный gate CI (ТЗ 16).

## Регенерация

```bash
curl -o /tmp/ru_50k.txt https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/ru/ru_50k.txt
curl -o /tmp/en_50k.txt https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/en/en_50k.txt
python3 Tools/generate_language_data.py /tmp/ru_50k.txt ru Sources/SmartSwitcherKit/Resources/ru_words.txt Sources/SmartSwitcherKit/Resources/ru_bigrams.tsv
python3 Tools/generate_language_data.py /tmp/en_50k.txt en Sources/SmartSwitcherKit/Resources/en_words.txt Sources/SmartSwitcherKit/Resources/en_bigrams.tsv
```

## Добавление нового языка детекта

1. Раскладка: пара в `Layout` + таблицы в `LayoutMapping`.
2. Данные: `<lang>_words.txt`, `<lang>_bigrams.tsv` + регистрация ресурсов
   в Package.swift.
3. Словарь/модель: ветки в `DictionaryService`/`NGramModel`.
4. Корпус в оценочный стенд.

Язык интерфейса (раздел 18 ТЗ) добавляется независимо: новый `<lang>.lproj`.
