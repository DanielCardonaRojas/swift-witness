//
//  ErasableWitness.swift
//  Witness
//
//  Created by Daniel Cardona on 2/07/25.
//

public protocol ErasableWitness {
    associatedtype Erased
    typealias Table = WitnessLookUpTable<Erased>
    func erased() -> Erased
    var erasedType: String { get }
}

public extension ErasableWitness {
    var erasedType: String {
        let metatype = type(of: self)
        let parsed = MetatypeParser.parse(metatype)
        return parsed.genericArguments[0].name
    }

    func registered(strategy: String? = nil) -> Self {
        register(strategy: strategy)
        return self
    }

    func register(strategy: String? = nil) {
        let table = Table()
        table.register(self, label: strategy ?? "default")
    }
}

