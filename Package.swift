// swift-tools-version:5.4

import PackageDescription

let package = Package(
    name: "LocalNote",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .library(name: "LocalNoteCore", targets: ["LocalNoteCore"]),
        .executable(name: "LocalNote", targets: ["LocalNoteApp"]),
        .executable(name: "LocalNoteTests", targets: ["LocalNoteTests"])
    ],
    targets: [
        .target(
            name: "LocalNoteCore",
            linkerSettings: [
                .linkedFramework("Security")
            ]
        ),
        .executableTarget(
            name: "LocalNoteApp",
            dependencies: ["LocalNoteCore"]
        ),
        .executableTarget(
            name: "LocalNoteTests",
            dependencies: ["LocalNoteCore"]
        )
    ]
)
