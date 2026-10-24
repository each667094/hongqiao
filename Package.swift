// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Hongqiao",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Hongqiao", targets: ["HongqiaoDesktop"])],
    targets: [
        .target(name: "HongqiaoCore"),
        .target(name: "HongqiaoPeer", dependencies: ["HongqiaoCore"]),
        .executableTarget(name: "HongqiaoDesktop", dependencies: ["HongqiaoCore", "HongqiaoPeer"]),
        .executableTarget(name: "HongqiaoChecks", dependencies: ["HongqiaoCore", "HongqiaoPeer"], path: "Tests/HongqiaoCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
