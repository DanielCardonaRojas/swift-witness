
//
//  WitnessRegistry.swift
//  Witness
//
//  Created by Daniel Cardona on 1/07/25.
//

import Foundation

/// A thread-safe, global registry for managing `WitnessTable` instances.
///
/// This class provides a singleton `shared` instance that ensures a single,
/// unique `WitnessTable` exists for each witness type throughout the application.
public final class WitnessRegistry {
    /// The shared singleton instance of the registry.
    public static let shared = WitnessRegistry()

    private(set) var tables: [String: WitnessTable] = [:]
    private let lock = NSLock()

    // Private initializer to enforce singleton pattern.
    private init() {}

    /// Retrieves or creates a `WitnessTable` for a given witness type.
    ///
    /// This method guarantees that for any given `WitnessType`, the same instance
    /// of `WitnessTable` will be returned every time, creating it on first request.
    ///
    /// - Parameter witnessType: The type of the witness for which to get the table (e.g., `MyProtocolWitness.self`).
    /// - Returns: The unique `WitnessTable` instance for the specified type.
    public func table<WitnessType>(for witnessType: WitnessType.Type) -> WitnessTable {
        let parsedType = MetatypeParser.parse(witnessType)
        lock.lock()
        defer { lock.unlock() }

        let key = String(describing: parsedType.name)

        if let existingTable = tables[key] {
            return existingTable
        } else {
            let newTable = WitnessTable(name: key)
            tables[key] = newTable
            return newTable
        }
    }
}
