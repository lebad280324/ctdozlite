// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CTDoNative",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "CTDoNative", targets: ["CTDoNative"])],
    targets: [
        .target(name: "NativeBridge"),
        .executableTarget(name: "CTDoNative", dependencies: ["NativeBridge"]),
        .testTarget(name: "NativeBridgeTests", dependencies: ["NativeBridge"]),
        .testTarget(name: "CTDoNativeTests", dependencies: ["CTDoNative", "NativeBridge"])
    ]
)
