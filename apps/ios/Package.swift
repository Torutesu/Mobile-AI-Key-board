// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MobileAIKeyboardCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "MobileAIKeyboardCore", targets: ["MobileAIKeyboardCore"])
    ],
    targets: [
        .target(
            name: "MobileAIKeyboardCore",
            path: "Sources/MobileAIKeyboardCore"
        ),
        .testTarget(
            name: "MobileAIKeyboardCoreTests",
            dependencies: ["MobileAIKeyboardCore"],
            path: "Tests/MobileAIKeyboardCoreTests"
        )
    ]
)
