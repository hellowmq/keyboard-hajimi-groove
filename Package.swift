// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "KeyboardHajimiGroove",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "keyboard-hajimi-groove",
            targets: ["KeyboardHajimiGroove"]
        )
    ],
    targets: [
        .target(
            name: "KeyboardHajimiGrooveCore"
        ),
        .executableTarget(
            name: "KeyboardHajimiGroove",
            dependencies: ["KeyboardHajimiGrooveCore"],
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation")
            ]
        ),
        .testTarget(
            name: "KeyboardHajimiGrooveCoreTests",
            dependencies: ["KeyboardHajimiGrooveCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
