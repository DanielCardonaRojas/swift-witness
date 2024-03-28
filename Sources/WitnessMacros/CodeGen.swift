//
//  File.swift
//  
//
//  Created by Daniel Cardona on 27/03/24.
//

import SwiftSyntax
import SwiftSyntaxBuilder

struct MacroError: Error {
  let message: String
}

public enum WitnessGenerator {
  static let genericLabel = "A"

  public static func processProtocol(protocolDecl: ProtocolDeclSyntax) throws -> [DeclSyntax] {
    let structDecl = StructDeclSyntax(
      name: "\(raw: protocolDecl.name.text)Witness",
      genericParameterClause: GenericParameterClauseSyntax(parameters: GenericParameterListSyntax(arrayLiteral: GenericParameterSyntax(name: TokenSyntax(stringLiteral: Self.genericLabel)))),
      memberBlock: MemberBlockSyntax(
        members: MemberBlockItemListSyntax(itemsBuilder: {
          for member in protocolDecl.memberBlock.members {
            if let functionDecl = member.decl.as(FunctionDeclSyntax.self) {
              MemberBlockItemSyntax(decl: processProtocolRequirement(functionDecl))
            } else {

            }
          }
        })
      )
    )

    return [
      DeclSyntax(structDecl)
    ]
  }

  static private func processProtocolRequirement(_ functionDecl: FunctionDeclSyntax) -> VariableDeclSyntax {
    VariableDeclSyntax(
      bindingSpecifier: TokenSyntax(stringLiteral: "let"),
      bindings: PatternBindingListSyntax(
        itemsBuilder: {
          PatternBindingListSyntax.Element(
            pattern: IdentifierPatternSyntax(
              identifier: functionDecl.name
            ),
            typeAnnotation: TypeAnnotationSyntax(
              type: FunctionTypeSyntax(
                parameters: TupleTypeElementListSyntax(itemsBuilder: {
                  // Convert mutating to inout
                  if functionDecl.modifiers.contains(where: { $0.name.text == TokenSyntax.keyword(.mutating).text}) {
                    TupleTypeElementSyntax(
                      type:  AttributedTypeSyntax(
                        specifier: .keyword(.inout),
                        baseType: IdentifierTypeSyntax(
                          name: TokenSyntax(stringLiteral: Self.genericLabel)
                        )
                      )
                    )

                  } else {
                    TupleTypeElementSyntax(
                      type: IdentifierTypeSyntax(
                        name: TokenSyntax(stringLiteral: Self.genericLabel)
                      )
                    )
                  }

                  for parameter in functionDecl.signature.parameterClause.parameters {
                    if let identifierType = parameter.type.as(IdentifierTypeSyntax.self), identifierType.name.text == "Self" {
                      TupleTypeElementSyntax(
                        type: IdentifierTypeSyntax(
                          name: TokenSyntax(stringLiteral: Self.genericLabel)
                        )
                      )
                    } else {
                      TupleTypeElementSyntax(type: parameter.type)
                    }
                  }
                }), returnClause: ReturnClauseSyntax(
                  type: Self.replaceSelf(typeSyntax: functionDecl.signature.returnClause?.type ?? TypeSyntax(stringLiteral: "Void")))))
          )
        }
      )
    )
  }

  static func replaceSelf(typeSyntax: TypeSyntaxProtocol) -> TypeSyntaxProtocol {
    if let syntax = typeSyntax.as(IdentifierTypeSyntax.self), syntax.name.text == TokenSyntax.keyword(.Self).text {
      return IdentifierTypeSyntax(
        name: TokenSyntax(stringLiteral: Self.genericLabel)
      )
    }

    return typeSyntax
  }
}
