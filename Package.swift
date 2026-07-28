// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Fine",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CPty", path: "Sources/CPty"),
        .executableTarget(
            name: "Fine",
            dependencies: ["CPty"],
            path: "Sources/Fine",
            resources: [.copy("Terminal/Resources")]
        ),
        .testTarget(
            name: "FineTests",
            dependencies: ["Fine"],
            path: "Tests/FineTests"
        ),
    ]
)
