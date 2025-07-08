// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "Witness",
    platforms: [.macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .watchOS(.v6), .macCatalyst(.v13)],
    products: [
        .library(
            name: "Witness",
            targets: ["Witness"]
        ),
        .library(
            name: "WitnessGenerator",
            targets: ["Witness"]
        ),
        .executable(
            name: "WitnessClient",
            targets: ["WitnessClient"]
        ),
    ],
    dependencies: [
        // Depend on the Swift 5.9 release of SwiftSyntax
        .package(url: "https://github.com/apple/swift-syntax.git", from: "600.0.1"),
        .package(url: "https://github.com/pointfreeco/swift-macro-testing.git", from: "0.5.2")
    ],
    targets: [
        .macro(
            name: "WitnessMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                "Shared",
                "WitnessGenerator"
            ]
        ),

        // Library exposing the swift-syntax code generation
        .target(
            name: "WitnessGenerator",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                "Shared"
            ]
        ),

        // Library that exposes a macro as part of its API, which is used in client programs.
        .target(name: "Witness", dependencies: ["WitnessMacros", "Shared"]),
        .target(name: "Shared"),

        // A CLI that uses the macro to generate code in new files
        .executableTarget(name: "WitnessClient", dependencies: ["Witness"]),

        // Test targets
        .testTarget(
            name: "WitnessTests",
            dependencies: [
                "WitnessMacros",
                "WitnessGenerator",
                "Shared",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
                .product(name: "MacroTesting", package: "swift-macro-testing")
            ]
        ),
        .testTarget(
            name: "SharedTests",
            dependencies: [
                "Shared",
                "Witness",
                "WitnessGenerator"
            ]
        ),
    ]
)
