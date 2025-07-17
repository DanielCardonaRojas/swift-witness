//
//  LookedUp.swift
//  swift-witness
//
//  Created by Daniel Cardona on 17/07/25.
//

@propertyWrapper
struct LookedUp<WitnessType> {
    var wrappedValue: WitnessType
    var strategy: String

    init(strategy: String = "default") {
        self.strategy = strategy
        let parsedType = MetatypeParser.parse(WitnessType.self)
        let innerGeneric = parsedType.genericArguments[0].name
        guard let witness = WitnessLookUpTable<WitnessType>().witness(for: "\(innerGeneric)", label: strategy) else {
            fatalError("Witness \(WitnessType.self) is not registered for strategy: \(strategy)")
        }
        self.wrappedValue = witness
    }
}

