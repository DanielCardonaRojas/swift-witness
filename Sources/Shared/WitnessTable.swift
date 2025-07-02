//
//  WitnessTable.swift
//  Witness
//
//  Created by Daniel Cardona on 30/06/25.
//

/// A table storing witnesses by types and strategy
public class WitnessTable {
    /// The name identifying the types of witnesses stored in the table instance
    let name: String

    public init(name: String) {
        self.name = name
    }

    /// A dictionary storing witnesses by type and strategy
    var witnesses: [String: [String: Any]] = [:]

    public func read(type: String, label: String?) -> Any? {
        witnesses[type]?[label ?? "default"]
    }

    public func read<T>(type: T.Type, label: String?) -> Any? {
        witnesses["\(type)"]?[label ?? "default"]
    }

    public func write<T>(type: T.Type, label: String?, witness: Any) {
        write(type: "\(type)", label: label, witness: witness)
    }

    public func write(type: String, label: String?, witness: Any) {
        let strategy = label ?? "default"
        if witnesses[type] != nil {
            witnesses[type]?[strategy] = witness
        } else {
            witnesses[type] = [strategy: witness]
        }
    }
}

