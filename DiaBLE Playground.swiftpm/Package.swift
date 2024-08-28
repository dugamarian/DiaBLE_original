// swift-tools-version: 5.6

// WARNING:
// This file is automatically generated.
// Do not edit it by hand because the contents will be replaced.

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "DiaBLE Playground",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "DiaBLE Playground",
            targets: ["AppModule"],
            bundleIdentifier: "name.DiaBLE-Playground",
            teamIdentifier: "Z25SC9UDC8",
            displayVersion: "0.0.1",
            bundleVersion: "1",
            appIcon: .asset("AppIcon"),
            accentColor: .asset("AccentColor"),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ],
            capabilities: [
                .bluetoothAlways(purposeString: "DiaBLE uses Bluetooth to receive data from glucose sensors."),
                .calendars(purposeString: "DiaBLE creates events to be displayed in Apple Watch complications."),
                .outgoingNetworkConnections(),
                .fileAccess(.userSelectedFiles, mode: .readWrite)
            ],
            appCategory: .healthcareFitness
        )
    ],
    dependencies: [
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift", "1.8.3"..<"2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            dependencies: [
                .product(name: "CryptoSwift", package: "cryptoswift")
            ],
            path: ".",
            resources: [
                .process("Resources")
            ]
        )
    ]
)