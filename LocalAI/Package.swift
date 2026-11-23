// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CooolLocalAI",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "CooolPM-AI", targets: ["CooolPMAI"])],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "2.29.3")
    ],
    targets: [
        .executableTarget(name: "CooolPMAI", dependencies: [
            .product(name: "MLXLLM", package: "mlx-swift-lm"),
            .product(name: "MLXLMCommon", package: "mlx-swift-lm")
        ])
    ]
)
