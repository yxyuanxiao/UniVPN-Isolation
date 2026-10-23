// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "UniVPNIsolationMenuBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "UniVPNMenuBar", targets: ["UniVPNMenuBar"])
    ],
    targets: [
        .executableTarget(
            name: "UniVPNMenuBar",
            path: "Sources"
        )
    ]
)
