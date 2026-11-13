// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mPIE",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "mPIECore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "mPIE", dependencies: ["mPIECore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "mPIETests", dependencies: ["mPIECore"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
