//
//  WitnessLookup.swift
//  Witness
//
//  Created by Daniel Cardona on 30/06/25.
//

/// Helper for reducing code generation on specific witness tables
public protocol WitnessLookUp {
    associatedtype WitnessType
    var table: WitnessTable { get }
}

public extension WitnessLookUp {
    func witness(for type: String, label: String? = nil) -> WitnessType? {
        table.read(type: type, label: label) as? WitnessType
    }

    func witness<A>(for type: A.Type, label: String? = nil) -> WitnessType? {
        table.read(type: "\(type)", label: label) as? WitnessType
    }
}

