//
//  WitnessTableTests.swift
//  Witness
//
//  Created by Daniel Cardona on 30/06/25.
//


import XCTest
@testable import Shared

final class WitnessTableTests: XCTestCase {

    func testRegistersWitnessByLabel() {
        var table = WitnessTable()
        table.write(type: Int.self, label: "sum", witness: Combining<Int>.sum)
        table.write(type: Int.self, label: "prod", witness: Combining<Int>.prod)
        XCTAssertNotNil(table.read(type: Int.self, label: "prod"))
        XCTAssertNotNil(table.read(type: Int.self, label: "sum"))
    }

    func testRegistersUnLabeledWitness() {
        var table = WitnessTable()
        table.write(type: Int.self, label: nil, witness: Combining<Int>.sum)
        let witness = table.read(type: Int.self, label: nil)
        XCTAssertNotNil(witness)
    }

}

