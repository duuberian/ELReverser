// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ELReverser",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "ELReverser",
            targets: ["ELReverser"]
        )
    ],
    targets: [
        .executableTarget(
            name: "ELReverser"
        )
    ]
)
