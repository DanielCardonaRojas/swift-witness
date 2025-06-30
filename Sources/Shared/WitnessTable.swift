//
//  WitnessTable.swift
//  Witness
//
//  Created by Daniel Cardona on 30/06/25.
//

/// A table storing witnesses by types and strategy
public struct WitnessTable {
    public init() { }

    /// A dictionary storing witnesses by type and strategy
    var witnesses: [String: [String: Any]] = [:]
    func read(type: String, label: String?) -> Any? {
        witnesses[type]?[label ?? "default"]
    }

    func read<T>(type: T.Type, label: String?) -> Any? {
        witnesses["\(type)"]?[label ?? "default"]
    }

    mutating func write<T>(type: T.Type, label: String?, witness: Any) {
        write(type: "\(type)", label: label, witness: witness)
    }

    mutating func write(type: String, label: String?, witness: Any) {
        let strategy = label ?? "default"
        if witnesses[type] != nil {
            witnesses[type]?[strategy] = witness
        } else {
            witnesses[type] = [strategy: witness]
        }
    }
}

