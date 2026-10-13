// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CPAMCMenuBar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "cpamc-menubar", targets: ["CPAMCMenuBar"]),
        .executable(name: "cpamc-quota-check", targets: ["QuotaCheck"]),
    ],
    targets: [
        .target(name: "QuotaCore"),
        .executableTarget(name: "CPAMCMenuBar", dependencies: ["QuotaCore"]),
        .executableTarget(name: "QuotaCheck", dependencies: ["QuotaCore"]),
        .testTarget(name: "QuotaCoreTests", dependencies: ["QuotaCore"]),
    ],
    swiftLanguageModes: [.v5]
)
