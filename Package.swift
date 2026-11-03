// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LocalAIAgent",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LocalAIAgent", targets: ["LocalAIAgent"])
    ],
    targets: [
        // Thin C layer for Apple SMC + HID temperature sensors (struct layouts are easier in C).
        .target(
            name: "SensorsC",
            path: "Sources/SensorsC",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation"),
            ]
        ),
        .executableTarget(
            name: "LocalAIAgent",
            dependencies: ["SensorsC"],
            path: "Sources/LocalAIAgent",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalPerformanceShaders"),
            ]
        ),
    ]
)
