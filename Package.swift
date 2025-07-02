// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "Witness",
    platforms: [.macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .watchOS(.v6), .macCatalyst(.v13)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Witness",
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
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        // Macro implementation that performs the source transformation of a macro.
        .macro(
            name: "WitnessMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                "Shared"
            ]
        ),

        // Library that exposes a macro as part of its API, which is used in client programs.
        .target(name: "Witness", dependencies: ["WitnessMacros", "Shared"]),
        .target(name: "Shared"),

        // A client of the library, which is able to use the macro in its own code.
        .executableTarget(name: "WitnessClient", dependencies: ["Witness"]),

        // A test target used to develop the macro implementation.
        .testTarget(
            name: "WitnessTests",
            dependencies: [
                "WitnessMacros",
                "Shared",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
                .product(name: "MacroTesting", package: "swift-macro-testing")
            ]
        ),
        .testTarget(
            name: "SharedTests",
            dependencies: [ "Shared", "Witness"]
        ),
    ]
)
