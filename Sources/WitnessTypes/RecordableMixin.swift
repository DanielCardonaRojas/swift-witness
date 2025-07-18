//
//  StoredWitnessMixin.swift
//  swift-witness
//
//  Created by Daniel Cardona on 17/07/25.
//

/// A mixin protocol that provides convenience methods for a witness to register itself in the global `WitnessLookUpTable`.
///
/// Conforming to `RecordableMixin` allows a witness implementation to easily store itself
/// so it can be retrieved later using `@LookedUp` or `WitnessLookUpTable`.
public protocol RecordableMixin { }

public extension RecordableMixin {
    /// Registers the conforming instance as a witness for a given strategy.
    ///
    /// This method writes the instance (`self`) into the `WitnessLookUpTable` associated
    /// with its type. The lookup key is derived from the first generic argument of the instance's type.
    ///
    /// - Parameter strategy: A string label to identify this specific witness registration.
    func register(strategy: String) {
        let table = WitnessLookUpTable<Self>().table
        let parsedType = MetatypeParser.parse(Self.self)
        table.write(
            type: parsedType.genericArguments[0].name,
            label: strategy,
            witness: self
        )
    }

    /// Registers the instance and returns it, allowing for fluent interface chaining.
    ///
    /// - Parameter strategy: A string label to identify this specific witness registration.
    /// - Returns: The instance (`self`) after registering it.
    func registered(strategy: String) -> Self {
        register(strategy: strategy)
        return self
    }
 }
