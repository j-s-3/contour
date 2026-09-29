// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "Contour",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Contour",
            path: "Sources/Contour",
            resources: [.copy("Resources/AppIcon.icns")],
            swiftSettings: [
                .swiftLanguageMode(.v6)
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
