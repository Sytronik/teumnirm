// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Teumnirm",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Teumnirm",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("CoreGraphics"),
            ]
        )
    ]
)
