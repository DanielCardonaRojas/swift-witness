//
//  Untitled.swift
//  Witness
//
//  Created by Daniel Cardona on 3/01/25.
//

import Foundation

public struct WitnessOptions: OptionSet {
    public let rawValue: Int

    /// Generate a `transform` method that will allow to convert the witness with `map` and/or `pullback`.
    public static let utilities = WitnessOptions(rawValue: 1 << 0)
    /// Generate an initializer creating a Witness from a conformance to the protocol
    public static let conformanceInit = WitnessOptions(rawValue: 1 << 1)
    /// Generate a struct that generate a protocol conformance
    public static let synthesizedConformance = WitnessOptions(rawValue: 1 << 2)

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    // Emulate RawRepresentable from String for convenience
    public init?(stringLiteral: String) {
        var combinedOptions: WitnessOptions = []
        let cleanedString = stringLiteral.replacingOccurrences(of: #"[\[\]. ]"#, with: "", options: .regularExpression)
        let components = cleanedString.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        for component in components {
            switch component {
            case "utilities":
                combinedOptions.formUnion(.utilities)
            case "conformanceInit":
                combinedOptions.formUnion(.conformanceInit)
            case "synthesizedConformance":
                combinedOptions.formUnion(.synthesizedConformance)
            case "": // Handle empty string if there are trailing commas or empty array
                continue
            default:
                // If any component is unrecognized, the whole initialization fails
                return nil
            }
        }
        self = combinedOptions
    }

    public var identifiers: [String] {
        var names: [String] = []
        if contains(.utilities) { names.append("utilities") }
        if contains(.conformanceInit) { names.append("conformanceInit") }
        if contains(.synthesizedConformance) { names.append("synthesizedConformance") }
        return names
    }
}


