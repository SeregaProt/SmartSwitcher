// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SmartSwitcher",
    defaultLocalization: "ru",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "SmartSwitcher", targets: ["SmartSwitcher"]),
        .library(name: "SmartSwitcherKit", targets: ["SmartSwitcherKit"]),
    ],
    targets: [
        .target(
            name: "SmartSwitcherKit",
            resources: [
                .copy("Resources/ru_words.txt"),
                .copy("Resources/en_words.txt"),
                .copy("Resources/ru_bigrams.tsv"),
                .copy("Resources/en_bigrams.tsv"),
                .process("Resources/ru.lproj"),
                .process("Resources/en.lproj"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "SmartSwitcher",
            dependencies: ["SmartSwitcherKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Собственный лёгкий тест-раннер: Command Line Tools не содержат
        // XCTest/Testing. При работе из полного Xcode тесты переводятся
        // на swift-testing без изменения проверок.
        .executableTarget(
            name: "SmartSwitcherChecks",
            dependencies: ["SmartSwitcherKit"],
            path: "Tests/SmartSwitcherChecks",
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Интеграционный тест (ТЗ 7.1): реальный SwitcherEngine на синтетических
        // событиях + живая вставка текста в собственное окно. Не требует прав
        // Accessibility (события подаются в engine.handle напрямую, минуя CGEventTap).
        .executableTarget(
            name: "SmartSwitcherIntegration",
            dependencies: ["SmartSwitcherKit"],
            path: "Tests/SmartSwitcherIntegration",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
