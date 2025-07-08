//
//  Types.swift
//  Witness
//
//  Created by Daniel Cardona on 3/01/25.
//

enum Variance: Equatable {
  case contravariant
  case covariant
  case invariant
}

enum TransformedWitnessSemantic: String {
  case iso
  case pullback
  case map
}

enum RequirementKind: Equatable {
  case function
  case variable
  case witness
}
