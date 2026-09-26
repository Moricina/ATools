// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ATools",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "ATools", targets: ["ATools"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "ATools",
            dependencies: [],
            path: "Sources/atools",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreServices"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("QuickLookThumbnailing")
            ]
        )
    ]
)
