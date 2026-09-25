// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "Contour",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Contour",
            path: "Sources/Contour",
            swiftSettings: [
                .swiftLanguageMode(.v5) // Observation + async UI code; keep migration friction low for MVP
            ]
        ),
        .testTarget(
            name: "ContourTests",
            dependencies: ["Contour"],
            path: "Tests/ContourTests",
            resources: [.copy("Fixtures")]
        )
    ]
)
