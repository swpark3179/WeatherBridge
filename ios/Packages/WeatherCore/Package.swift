// swift-tools-version: 6.0
import PackageDescription

// 플랫폼 독립 로직(Live Activity 페이로드 모델, 강수 등급).
// Foundation만 사용해 Linux에서도 `swift test`로 검증할 수 있게 유지한다.
let package = Package(
    name: "WeatherCore",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "WeatherCore", targets: ["WeatherCore"]),
    ],
    targets: [
        .target(name: "WeatherCore"),
        .testTarget(
            name: "WeatherCoreTests",
            dependencies: ["WeatherCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
