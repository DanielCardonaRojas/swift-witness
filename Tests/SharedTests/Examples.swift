//
//  Examples.swift
//  Witness
//
//  Created by Daniel Cardona on 2/07/25.
//
import Witness
import Shared

@Witnessed([.utilities, .conformanceInit])
protocol Combinable {
  func combine(_ other: Self) -> Self
}

typealias Combining<T> = CombinableWitness<T>

extension Combining where A: Numeric {
  static var sum: Combining {
    return Combining { $0 + $1 }
  }

  static var prod: Combining {
    return Combining { $0 + $1 }
  }
}

extension Combining where A: RangeReplaceableCollection {
  static var concat: Combining {
    return Combining { $0 + $1 }
  }
}

@Witnessed([.synthesizedConformance, .utilities])
protocol Fake {
    func fake() -> Self
}

extension FakeWitness where A == Int {
    static let negative = FakeWitness(
        fake: { _ in Int.random(in: 0..<100) * -1 }
    )
}
