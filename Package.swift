// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CloudNotes",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "CloudNotes",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift")
            ],
            path: "Sources/CloudNotes"
        )
    ]
)
