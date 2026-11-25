// swift-tools-version: 5.9
import PackageDescription

// DO NOT MODIFY THIS FILE - managed by Capacitor CLI commands
let package = Package(
    name: "CapApp-SPM",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "CapApp-SPM",
            targets: ["CapApp-SPM"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", exact: "8.6.0"),
        .package(name: "CapacitorFilesystem", path: "../../../node_modules/.bun/@capacitor+filesystem@8.1.5+6ab6186627aac117/node_modules/@capacitor/filesystem"),
        .package(name: "CapacitorSplashScreen", path: "../../../node_modules/.bun/@capacitor+splash-screen@8.0.2+6ab6186627aac117/node_modules/@capacitor/splash-screen"),
        .package(name: "CapgoCapacitorDownloader", path: "../../../node_modules/.bun/@capgo+capacitor-downloader@file+..+e229c1357836e5a2/node_modules/@capgo/capacitor-downloader"),
        .package(name: "CapgoCapacitorUpdater", path: "../../../node_modules/.bun/@capgo+capacitor-updater@8.54.2+6ab6186627aac117/node_modules/@capgo/capacitor-updater")
    ],
    targets: [
        .target(
            name: "CapApp-SPM",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm"),
                .product(name: "CapacitorFilesystem", package: "CapacitorFilesystem"),
                .product(name: "CapacitorSplashScreen", package: "CapacitorSplashScreen"),
                .product(name: "CapgoCapacitorDownloader", package: "CapgoCapacitorDownloader"),
                .product(name: "CapgoCapacitorUpdater", package: "CapgoCapacitorUpdater")
            ]
        )
    ]
)
