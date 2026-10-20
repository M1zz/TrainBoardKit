// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TrainBoardKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)   // 판정 시험을 `swift test` 로 돌리려고. 카메라는 iOS 에서만 들어간다.
    ],
    products: [
        .library(name: "TrainBoardKit", targets: ["TrainBoardKit"])
    ],
    targets: [
        .target(name: "TrainBoardKit"),
        .testTarget(name: "TrainBoardKitTests", dependencies: ["TrainBoardKit"])
    ]
)
