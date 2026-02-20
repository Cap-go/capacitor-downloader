// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CapgoCapacitorDownloader",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "CapgoCapacitorDownloader",
            targets: ["CapacitorDownloaderPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "8.1.0")
    ],
    targets: [
        .target(
            name: "CapacitorDownloaderPlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ],
            path: "ios/Sources/CapacitorDownloaderPlugin"),
        .testTarget(
            name: "CapacitorDownloaderPluginTests",
            dependencies: ["CapacitorDownloaderPlugin"],
            path: "ios/Tests/CapacitorDownloaderPluginTests")
    ]
)
