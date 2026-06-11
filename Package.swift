// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CloudNotes",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "CloudNotes",
            path: "Sources/CloudNotes"
        )
    ]
)
