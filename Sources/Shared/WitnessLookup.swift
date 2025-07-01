//
//  WitnessLookup.swift
//  Witness
//
//  Created by Daniel Cardona on 30/06/25.
//

public protocol ErasableWitness {
    associatedtype Erased
    func erased() -> Erased
    var erasedType: String { get }
}

public extension ErasableWitness {
    var erasedType: String {
        let metatype = type(of: self)
        let parsed = MetatypeParser.parse(metatype)
        return parsed.genericArguments[0].name
    }
}

/// Helper for reducing code generation on specific witness tables
public struct WitnessLookUpTable<WitnessType> {
    var witnessType: Any.Type
    /// Erased type for the witness. For example `Witness<Any>`
    var table: WitnessTable

    public init(table: WitnessTable) {
        self.witnessType = WitnessType.self
        self.table = table
    }

    public func witness(for type: String, label: String? = nil) -> WitnessType? {
        table.read(type: type, label: label) as? WitnessType
    }

    public func witness<A>(for type: A.Type, label: String? = nil) -> WitnessType? {
        table.read(type: "\(type)", label: label) as? WitnessType
    }

    public func register<Witness: ErasableWitness>(
        _ witness: Witness,
        label: String? = nil
    ) {
        let erasedWitness = witness.erased()
        table.write(
            type: witness.erasedType,
            label: label,
            witness: erasedWitness
        )
    }
}

