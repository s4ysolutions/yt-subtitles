// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "yt-subtitles",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "yt-subtitles",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ],
            path: "Sources/yt-subtitles"
        ),
        .testTarget(
            name: "yt-subtitlesTests",
            dependencies: ["yt-subtitles"],
            path: "Tests/yt-subtitlesTests"
        ),
    ]
)
