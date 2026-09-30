// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ReadImageOnDevice",
    // Vision は macOS 10.15 以降で動作するため、デプロイ先は macOS 11。
    // Foundation Models（macOS 26/27）は #if canImport と #available で実行時・
    // コンパイル時に切り替え、対応していない OS では Vision の経路にフォールバックする。
    // 真に minos 11.0 を得るには Command Line Tools(SDK 26) でのビルドが必要（README 参照）。
    platforms: [.macOS(.v11)],
    products: [
        .library(name: "ReadImageOnDevice", targets: ["ReadImageOnDevice"]),
        .executable(name: "readimage", targets: ["readimage"]),
    ],
    targets: [
        // オンデバイス画像リーダー本体（Vision + 任意で Foundation Models）
        .target(
            name: "ReadImageOnDevice",
            path: "Sources/ReadImageOnDevice"
        ),
        // 共通規格風のCLI。標準入出力で JSON / プレーンテキストを返す。
        .executableTarget(
            name: "readimage",
            dependencies: ["ReadImageOnDevice"],
            path: "Sources/readimage"
        ),
        .testTarget(
            name: "ReadImageOnDeviceTests",
            dependencies: ["ReadImageOnDevice"],
            path: "Tests/ReadImageOnDeviceTests"
        ),
    ]
)
