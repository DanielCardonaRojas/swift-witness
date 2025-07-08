//
//  TypeContainsVisitor.swift
//  Witness
//
//  Created by Daniel Cardona on 6/01/25.
//

import SwiftSyntax
import SwiftSyntaxBuilder

/// A visitor that inspects a subtree of type syntax and determines
/// if it contains the given `targetTypeName`.
final class TypeContainsVisitor: SyntaxVisitor {
    private let targetTypeName: String
    private var foundMatch = false

    init(targetTypeName: String) {
        self.targetTypeName = targetTypeName
        super.init(viewMode: .sourceAccurate)
    }

    /// Returns true if this visitor found a match while visiting.
    var containsTargetType: Bool { foundMatch }

    /// Instead of visiting every node in the entire file (e.g. large AST),
    /// you can call `visitor.visit(someTypeSyntax)` to restrict to that subtree.
  override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        // e.g., `Int`, `String`, `MyType`
        if node.name.text == targetTypeName {
            foundMatch = true
            // You can stop visiting further if desired
            return .skipChildren
        }
        return .visitChildren
    }

  override func visit(_ node: MemberTypeSyntax) -> SyntaxVisitorContinueKind {
        // e.g., `Swift.Int` or `Foundation.Date`
        // Check last name piece first:
        if node.name.text == targetTypeName {
            foundMatch = true
            return .skipChildren
        }
        return .visitChildren
    }

    // You can override visits for OptionalType, ArrayType, etc.,
    // but note you typically don’t need to do so if you're
    // relying on visiting children, since the contained `wrappedType`
    // or `elementType` eventually leads to visiting a `SimpleTypeIdentifier`.

    // For completeness:

    override func visit(_ node: OptionalTypeSyntax) -> SyntaxVisitorContinueKind {
        // e.g., `Int?` => visits `Int` next
        return .visitChildren
    }

    override func visit(_ node: ArrayTypeSyntax) -> SyntaxVisitorContinueKind {
        // e.g., `[String]` => visits `String` next
        return .visitChildren
    }
}

extension TypeAnnotationSyntax {
  /// A convenience function that uses the visitor to check if a `TypeAnnotationSyntax` contains
  /// a type name. This replicates the logic of the previous function, but uses a visitor approach.
  func contains(targetTypeName: String) -> Bool {
      let visitor = TypeContainsVisitor(targetTypeName: targetTypeName)
      // Visit only the type portion
      visitor.walk(self.type)
      return visitor.containsTargetType
  }
}
