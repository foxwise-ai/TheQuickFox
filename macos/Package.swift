// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TheQuickFox",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "TheQuickFox",
            targets: ["TheQuickFox"]
        ),
        .executable(
            name: "capture-cli",
            targets: ["capture-cli"]
        ),
        .executable(
            name: "ocr-cli",
            targets: ["OCRCli"]
        ),
        .library(
            name: "TheQuickFoxCore",
            targets: ["TheQuickFoxCore"]
        )
    ],
    dependencies: [
        // Lightweight helper for defining global shortcuts on macOS.
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "0.3.0"),
        // Markdown renderer for macOS
        .package(url: "https://github.com/johnxnguyen/Down", from: "0.11.0"),
        // Sparkle framework for automatic app updates
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        // TOON format encoder for token-efficient LLM context
        .package(url: "https://github.com/toon-format/toon-swift.git", from: "0.3.0")
    ],
    targets: [
        .target(
            name: "TheQuickFoxCore",
            dependencies: [
                .product(name: "ToonFormat", package: "toon-swift")
            ],
            path: "Sources/TheQuickFoxCore"
        ),
        .executableTarget(
            name: "TheQuickFox",
            dependencies: [
                "TheQuickFoxCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "Down", package: "Down"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "ToonFormat", package: "toon-swift")
            ],
            path: "Sources/TheQuickFox",
            exclude: ["CLI"],
            resources: [
                .process("Onboarding/Resources"),
                .process("Upgrade/Resources"),
                .process("Reminder/Resources"),
                .process("Visual/MorphShader.metal"),
                .process("../../Resources")
            ]
        ),
        .executableTarget(
            name: "capture-cli",
            dependencies: [],
            path: "Sources/TheQuickFox/CLI"
        ),
        .executableTarget(
            name: "OCRCli",
            dependencies: ["TheQuickFoxCore"],
            path: "Sources/OCRCli"
        ),
        .testTarget(
            name: "TheQuickFoxTests",
            dependencies: ["TheQuickFox"],
            path: "Tests/TheQuickFoxTests"
        )
    ]
)
