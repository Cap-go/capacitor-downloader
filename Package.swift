// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CapgoCapacitorAccelerometer",
    platforms: [.iOS(.v14)],
    products: [
        .library(
            name: "CapgoCapacitorAccelerometer",
            targets: ["CapacitorAccelerometerPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "CapacitorAccelerometerPlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ],
            path: "ios/Sources/CapacitorAccelerometerPlugin"),
        .testTarget(
            name: "CapacitorAccelerometerPluginTests",
            dependencies: ["CapacitorAccelerometerPlugin"],
            path: "ios/Tests/CapacitorAccelerometerPluginTests")
    ]
)
