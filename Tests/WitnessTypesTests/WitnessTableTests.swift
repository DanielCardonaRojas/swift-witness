//
//  WitnessTableTests.swift
//  Witness
//
//  Created by Daniel Cardona on 30/06/25.
//


import XCTest
@testable import WitnessTypes

final class WitnessTableTests: XCTestCase {

    func testRegistersWitnessByLabel() {
        let table = WitnessTable(name: "Combinable")
        table.write(type: Int.self, label: "sum", witness: Combining<Int>.sum)
        table.write(type: Int.self, label: "prod", witness: Combining<Int>.prod)
        XCTAssertNotNil(table.read(type: Int.self, label: "prod"))
        XCTAssertNotNil(table.read(type: Int.self, label: "sum"))
    }

    func testRegistersUnLabeledWitness() {
        let table = WitnessTable(name: "Combinable")
        table.write(type: Int.self, label: nil, witness: Combining<Int>.sum)
        let witness = table.read(type: Int.self, label: nil)
        XCTAssertNotNil(witness)
    }

}

