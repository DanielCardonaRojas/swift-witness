
//
//  RecordableMixinTests.swift
//  WitnessTypesTests
//
//  Created by Daniel Cardona on 17/07/25.
//

import XCTest
@testable import Witness
@testable import WitnessTypes

class RecordableMixinTests: XCTestCase {
    func testRegisterAndLookUp() {
        let randomAgeGenerator = RandomNumberGeneratorWitness<String>(random: { _ in
            97
        }).registered(strategy: "mock")

        @LookedUp(strategy: "mock") var witness: RandomNumberGeneratorWitness<String>
        XCTAssertEqual(witness.random(""), randomAgeGenerator.random(""))
    }
}


struct RandomNumberGeneratorWitness<A>: RecordableMixin {
    let random: (A) -> Double
}
