// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Tenfe",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Tenfe", targets: ["Tenfe"])
    ],
    targets: [
        .executableTarget(
            name: "Tenfe",
            path: "Sources"
        )
    ]
)