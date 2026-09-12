// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Fine",
    platforms: [.macOS(.v14)],
    products: [
        // 대소문자 구분이 없는 APFS에서 `fine`은 앱 실행파일 `Fine`과 같은 경로가 되어
        // .build 안에서 서로를 덮어쓴다. 그래서 빌드 산출물은 fine-cli이고, 설치할 때
        // ~/bin/fine 으로 복사한다 (README 참고).
        .executable(name: "fine-cli", targets: ["FineCLI"]),
    ],
    targets: [
        .target(name: "CPty", path: "Sources/CPty"),
        .executableTarget(
            name: "Fine",
            dependencies: ["CPty"],
            path: "Sources/Fine",
            resources: [.copy("Terminal/Resources"), .process("HarnessIcons.xcassets")]
        ),
        .executableTarget(name: "FineCLI", path: "Sources/FineCLI"),
        .testTarget(
            name: "FineTests",
            dependencies: ["Fine"],
            path: "Tests/FineTests"
        ),
    ]
)
