// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tasklist",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Tasklist", targets: ["Tasklist"])],
    targets: [
        .target(name: "TasklistCore", resources: [.process("Resources")]),
        .executableTarget(name: "Tasklist", dependencies: ["TasklistCore"], resources: [.process("Assets.xcassets")]),
        .testTarget(name: "TasklistCoreTests", dependencies: ["TasklistCore"])
    ],
    swiftLanguageModes: [.v5]
)
