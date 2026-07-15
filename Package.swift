// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HVMeldeCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "HVMeldeCore", targets: ["HVMeldeCore"])
    ],
    targets: [
        .target(name: "HVMeldeCore"),
        .testTarget(
            name: "HVMeldeCoreTests",
            dependencies: ["HVMeldeCore"]
        )
    ]
)

