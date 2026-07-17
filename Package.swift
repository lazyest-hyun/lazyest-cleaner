// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LazyestCleaner",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LazyestCleaner", targets: ["LazyestCleaner"])
    ],
    targets: [
        .executableTarget(
            name: "LazyestCleaner",
            path: "Sources/LazyestCleaner",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Security"),
            ]
        ),
        .testTarget(
            name: "LazyestCleanerTests",
            dependencies: ["LazyestCleaner"],
            path: "Tests/LazyestCleanerTests"
        ),
    ]
)
