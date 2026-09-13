// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TidyBugCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TidyBugCore", targets: ["TidyBugCore"]),
    ],
    targets: [
        .target(
            name: "TidyBugCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "TidyBugCoreTests",
            dependencies: ["TidyBugCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
