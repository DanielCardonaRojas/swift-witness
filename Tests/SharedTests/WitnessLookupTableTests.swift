//
//  WitnessLookupTableTests.swift
//  Witness
//
//  Created by Daniel Cardona on 2/07/25.
//

import XCTest
@testable import Shared

final class WitnessLookupTableTests: XCTestCase {
    func testReadesRegisteredInExtension() {
        FakeWitness.negative.register()
        let witness = FakeWitness<Int>.Table().witness(for: Int.self)
        XCTAssertNotNil(witness)
    }
}

