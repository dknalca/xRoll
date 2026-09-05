// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "xRoll",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "XRollCore", targets: ["XRollCore"]),
        .executable(name: "xroll-preflight", targets: ["XRollPreflight"]),
        .executable(name: "xroll-latency", targets: ["XRollLatency"]),
        .executable(name: "xroll-play-kit", targets: ["XRollKitPlayer"]),
        .executable(name: "xroll-pads", targets: ["XRollPads"]),
        .executable(name: "xroll-map-pads", targets: ["XRollPadMapper"]),
        .executable(name: "xroll-preview", targets: ["XRollExercisePreview"]),
        .executable(name: "xroll-analyse-recording", targets: ["XRollRecordingAnalysis"])
    ],
    targets: [
        .target(
            name: "XRollCore",
            path: "Sources/XRollCore"
        ),
        .executableTarget(
            name: "XRollPreflight",
            dependencies: ["XRollCore"],
            path: "Sources/XRollPreflight"
        ),
        .executableTarget(
            name: "XRollLatency",
            dependencies: ["XRollCore"],
            path: "Sources/XRollLatency"
        ),
        .executableTarget(
            name: "XRollKitPlayer",
            dependencies: ["XRollCore"],
            path: "Sources/XRollKitPlayer"
        ),
        .executableTarget(
            name: "XRollPads",
            dependencies: ["XRollCore"],
            path: "Sources/XRollPads"
        ),
        .executableTarget(
            name: "XRollPadMapper",
            dependencies: ["XRollCore"],
            path: "Sources/XRollPadMapper"
        ),
        .executableTarget(
            name: "XRollExercisePreview",
            dependencies: ["XRollCore"],
            path: "Sources/XRollExercisePreview"
        ),
        .executableTarget(
            name: "XRollRecordingAnalysis",
            dependencies: ["XRollCore"],
            path: "Sources/XRollRecordingAnalysis"
        ),
        .testTarget(
            name: "XRollCoreTests",
            dependencies: ["XRollCore"],
            path: "Tests/XRollCoreTests"
        )
    ]
)
