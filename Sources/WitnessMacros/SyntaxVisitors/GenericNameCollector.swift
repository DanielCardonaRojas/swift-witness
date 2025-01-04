//
//  GenericNameCollector.swift
//  Witness
//
//  Created by Daniel Cardona on 3/01/25.
//
import SwiftSyntax

final class GenericNameCollector: SyntaxVisitor {
  /// The set of all generic names (e.g., T, U, V) declared in the function.
  private let declaredGenerics: Set<String>
  /// Accumulates the generic names found in the visited syntax.
  private(set) var foundGenerics = Set<String>()

  init(declaredGenerics: Set<String>) {
    self.declaredGenerics = declaredGenerics
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
    let name = node.name.text
    if declaredGenerics.contains(name) {
      foundGenerics.insert(name)
    }
    return .visitChildren
  }
}


