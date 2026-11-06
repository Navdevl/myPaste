// swift-tools-version:6.0
import PackageDescription

let swift5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "myPaste",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "myPaste", targets: ["myPaste"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        // 1.15.0 is the last release without #Preview macros, which need Xcode (not the Command Line Tools).
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", exact: "1.15.0"),
    ],
    targets: [
        .target(
            name: "MyPasteCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            path: "Sources/Core",
            swiftSettings: swift5
        ),
        .executableTarget(
            name: "myPaste",
            dependencies: ["MyPasteCore", "KeyboardShortcuts"],
            path: "Sources/App",
            swiftSettings: swift5
        ),
        .executableTarget(
            name: "myPasteUITests",
            dependencies: ["MyPasteCore"],
            path: "Tests/UITests",
            swiftSettings: swift5
        ),
        .testTarget(
            name: "MyPasteCoreTests",
            dependencies: ["MyPasteCore", .product(name: "GRDB", package: "GRDB.swift")],
            path: "Tests/MyPasteCoreTests",
            swiftSettings: swift5
        ),
    ]
)
