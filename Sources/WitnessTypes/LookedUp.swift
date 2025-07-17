//
//  LookedUp.swift
//  swift-witness
//
//  Created by Daniel Cardona on 17/07/25.
//

/// A property wrapper that looks up a witness from the global witness table.
///
/// `LookedUp` simplifies retrieving a registered witness for a specific type and strategy.
/// It uses the `WitnessLookUpTable` to find a witness that has been previously registered.
///
/// - Parameter WitnessType: The type of the witness to look up. This is typically a `Witness<P>` type, where `P` is Self.
@propertyWrapper
public struct LookedUp<WitnessType> {
    /// The resolved witness instance found by the lookup.
    public var wrappedValue: WitnessType

    /// The strategy used to look up the witness.
    var strategy: String

    /// Initializes the property wrapper by looking up a witness in the `WitnessLookUpTable`.
    ///
    /// The lookup is performed based on the generic `WitnessType` and the provided `strategy`.
    /// If a witness is not found, the program will terminate with a `fatalError`.
    ///
    /// - Parameter strategy: The registration strategy label to use for the lookup. Defaults to "default".
    public init(strategy: String? = nil) {
        self.strategy = strategy ?? "default"
        let parsedType = MetatypeParser.parse(WitnessType.self)
        let innerGeneric = parsedType.genericArguments[0].name
        guard let witness = WitnessLookUpTable<WitnessType>().witness(for: "\(innerGeneric)", label: strategy) else {
            fatalError("Witness \(WitnessType.self) is not registered for strategy: \(strategy)")
        }
        self.wrappedValue = witness
    }
}

