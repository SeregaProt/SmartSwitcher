import Carbon
import Foundation

/// Конвертация текста «как если бы те же клавиши нажали в другой раскладке».
public protocol LayoutConverting: AnyObject {
    /// nil — встретился символ, которого нет в раскладке-источнике
    /// (graceful degradation: такой ввод не трогаем).
    func convert(_ text: String, from source: Layout, to target: Layout) -> String?
    /// Может ли символ быть частью «слова» хотя бы в одной раскладке
    /// (буква или пунктуация, которая в другой раскладке — буква).
    func isMappable(_ ch: Character) -> Bool
}

public extension LayoutConverting {
    /// Нестрогая конвертация для выделенного текста: неизвестные символы
    /// (цифры, пробелы, эмодзи) остаются как есть.
    func convertLenient(_ text: String, from source: Layout, to target: Layout) -> String {
        var result = ""
        for ch in text {
            result += convert(String(ch), from: source, to: target) ?? String(ch)
        }
        return result
    }
}

/// Статическая таблица US QWERTY ↔ «Русская – ПК». Фолбэк и эталон для тестов.
public final class StaticLayoutConverter: LayoutConverting, Sendable {
    public init() {}

    public func convert(_ text: String, from source: Layout, to target: Layout) -> String? {
        switch (source, target) {
        case (.en, .ru): return LayoutMapping.toRussian(text)
        case (.ru, .en): return LayoutMapping.toEnglish(text)
        default: return text
        }
    }

    public func isMappable(_ ch: Character) -> Bool {
        LayoutMapping.enToRuTable[ch] != nil || LayoutMapping.ruToEnTable[ch] != nil
    }
}

/// Конвертер по реальным данным установленных раскладок (`UCKeyTranslate`):
/// поддерживает «Русскую» (Apple) и «Русскую – ПК», British, Dvorak, Colemak
/// и любые другие раскладки с языком en/ru. Таблицы строятся по физическим
/// клавишам: символ раскладки A → та же клавиша (и Shift) → символ раскладки B.
///
/// `rebuild` вызывается на главном потоке (TIS); `convert` — из любого потока.
///
/// `@unchecked Sendable`: таблицы защищены `lock`.
public final class SystemLayoutConverter: LayoutConverting, @unchecked Sendable {
    private struct Pair: Hashable {
        let source: Layout
        let target: Layout
    }

    /// Клавиши основного блока: буквы, цифры и пунктуация (без Return,
    /// Tab, Space). Номера — виртуальные коды ANSI/ISO-клавиатуры.
    private static let keyCodes: [UInt16] = Array(0...50).filter { ![36, 48, 49].contains($0) }
    private static let shiftState = UInt32((shiftKey >> 8) & 0xFF)

    private let lock = NSLock()
    private var tables: [Pair: [Character: Character]] = [:]
    private var mappable: Set<Character> = []
    private let fallback = StaticLayoutConverter()

    public init() {}

    /// Пересобрать таблицы по текущим input sources (главный поток).
    public func rebuild(sources: [Layout: TISInputSource]) {
        var keymaps: [Layout: [Int: Character]] = [:]
        for (layout, source) in sources {
            if let keymap = Self.keymap(of: source) { keymaps[layout] = keymap }
        }

        var newTables: [Pair: [Character: Character]] = [:]
        var newMappable = Set<Character>()
        for (source, sourceMap) in keymaps {
            // Сначала слоты без Shift (чётные): при совпадении символов
            // приоритет у них.
            let slots = sourceMap.keys.sorted { ($0 % 2, $0) < ($1 % 2, $1) }
            for (target, targetMap) in keymaps where target != source {
                var table: [Character: Character] = [:]
                for slot in slots {
                    guard let from = sourceMap[slot], let to = targetMap[slot],
                          table[from] == nil else { continue }
                    table[from] = to
                }
                newTables[Pair(source: source, target: target)] = table
            }
            for ch in sourceMap.values where ch.isLetter || ch.isPunctuation || ch.isSymbol {
                newMappable.insert(ch)
            }
        }

        lock.lock()
        tables = newTables
        mappable = newMappable
        lock.unlock()
        Log.brain.info("Таблицы раскладок пересобраны: \(newTables.count) пар")
    }

    public func convert(_ text: String, from source: Layout, to target: Layout) -> String? {
        guard source != target else { return text }
        lock.lock()
        let table = tables[Pair(source: source, target: target)]
        lock.unlock()
        guard let table, !table.isEmpty else {
            return fallback.convert(text, from: source, to: target)
        }
        var result = ""
        result.reserveCapacity(text.count)
        for ch in text {
            guard let mapped = table[ch] else { return nil }
            result.append(mapped)
        }
        return result
    }

    public func isMappable(_ ch: Character) -> Bool {
        if TokenUtils.isLatinLetter(ch) || TokenUtils.isCyrillicLetter(ch) { return true }
        lock.lock()
        let known = mappable.contains(ch)
        lock.unlock()
        return known || fallback.isMappable(ch)
    }

    // MARK: - UCKeyTranslate

    /// Символы раскладки по слотам: slot = keyCode * 2 + (shift ? 1 : 0).
    private static func keymap(of source: TISInputSource) -> [Int: Character]? {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        return data.withUnsafeBytes { buffer -> [Int: Character]? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return nil
            }
            var map: [Int: Character] = [:]
            for keyCode in keyCodes {
                for (shiftIndex, modifiers) in [UInt32(0), shiftState].enumerated() {
                    var deadKeyState: UInt32 = 0
                    var length = 0
                    var chars = [UniChar](repeating: 0, count: 4)
                    let status = UCKeyTranslate(
                        layout,
                        keyCode,
                        UInt16(kUCKeyActionDown),
                        modifiers,
                        UInt32(LMGetKbdType()),
                        OptionBits(kUCKeyTranslateNoDeadKeysMask),
                        &deadKeyState,
                        chars.count,
                        &length,
                        &chars
                    )
                    guard status == noErr, length > 0 else { continue }
                    let string = String(utf16CodeUnits: chars, count: length)
                    guard string.count == 1, let ch = string.first,
                          !ch.isWhitespace, !ch.isNewline else { continue }
                    map[Int(keyCode) * 2 + shiftIndex] = ch
                }
            }
            return map.isEmpty ? nil : map
        }
    }
}
