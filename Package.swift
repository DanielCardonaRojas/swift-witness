// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "swift-witness",
    platforms: [.macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .watchOS(.v6), .macCatalyst(.v13)],
    products: [
        .library(
            name: "Witness",
            targets: ["Witness"]
        ),
        .library(
            name: "WitnessGenerator",
            targets: ["WitnessGenerator"]
        ),
        .library(
            name: "WitnessTypes",
            targets: ["WitnessTypes"]
        ),
        .executable(
            name: "WitnessClient",
            targets: ["WitnessClient"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", from: "601.0.1"),
        .package(url: "https://github.com/pointfreeco/swift-macro-testing.git", from: "0.5.2")
    ],
    targets: [
        .macro(
            name: "WitnessMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                "WitnessTypes",
                "WitnessGenerator"
            ]
        ),

        // Library exposing the swift-syntax code generation
        .target(
            name: "WitnessGenerator",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                "WitnessTypes"
            ]
        ),

        // Library that exposes a macro as part of its API, which is used in client programs.
        .target(name: "Witness", dependencies: ["WitnessMacros", "WitnessTypes"]),
        // Library that exposes base types
        .target(name: "WitnessTypes"),

        // A CLI that uses the macro to generate code in new files
        .executableTarget(name: "WitnessClient", dependencies: ["Witness"]),

        // Test targets
        .testTarget(
            name: "WitnessTests",
            dependencies: [
                "WitnessMacros",
                "WitnessGenerator",
                "WitnessTypes",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
                .product(name: "MacroTesting", package: "swift-macro-testing")
            ]
        ),
        .testTarget(
            name: "WitnessTypesTests",
            dependencies: [
                "WitnessTypes",
                "Witness",
                "WitnessGenerator"
            ]
        ),
    ]
)
