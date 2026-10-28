import Foundation

/// Минимальный тест-раннер: Command Line Tools не включают XCTest/Testing.
/// Совместим по духу с swift-testing (#expect) для лёгкой миграции.
final class TestRunner {
    static let shared = TestRunner()

    private(set) var passed = 0
    private(set) var failed = 0
    private var currentSuite = ""

    func suite(_ name: String, _ body: () -> Void) {
        currentSuite = name
        print("▶︎ \(name)")
        body()
    }

    func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String,
        file: String = #file,
        line: Int = #line
    ) {
        if condition() {
            passed += 1
        } else {
            failed += 1
            let fileName = (file as NSString).lastPathComponent
            print("  ✗ [\(currentSuite)] \(message) (\(fileName):\(line))")
        }
    }

    func finish() -> Never {
        print("")
        if failed == 0 {
            print("✓ Все проверки пройдены: \(passed)")
            exit(0)
        } else {
            print("✗ Провалено: \(failed), пройдено: \(passed)")
            exit(1)
        }
    }
}

func suite(_ name: String, _ body: () -> Void) {
    TestRunner.shared.suite(name, body)
}

func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String,
    file: String = #file,
    line: Int = #line
) {
    TestRunner.shared.expect(condition(), message, file: file, line: line)
}
