// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "FluidMenuBarExtra",
    platforms: [.macOS(.v13)],
    products: [
        .library(
            name: "FluidMenuBarExtra",
            targets: ["FluidMenuBarExtra"]
        )
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "FluidMenuBarExtra",
            dependencies: []
        )
    ]
)
