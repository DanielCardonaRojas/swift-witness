//
//  StoredWitnessMixin.swift
//  swift-witness
//
//  Created by Daniel Cardona on 17/07/25.
//

protocol RecordableMixin { }

extension RecordableMixin {
    func register(strategy: String) {
        let table = WitnessLookUpTable<Self>().table
        let parsedType = MetatypeParser.parse(Self.self)
        table.write(
            type: parsedType.genericArguments[0].name,
            label: strategy,
            witness: self
        )
    }

    func registered(strategy: String) -> Self {
        register(strategy: strategy)
        return self
    }
 }
