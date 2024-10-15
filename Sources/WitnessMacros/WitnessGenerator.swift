//
//  WitnessGenerator.swift
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
      genericParameterClause: genericParameterClause(protocolDecl),
      memberBlock: MemberBlockSyntax(
        members: MemberBlockItemListSyntax(itemsBuilder: {
          if let inheritedTypes = protocolDecl.inheritanceClause?.inheritedTypes {
            for inheritedType in inheritedTypes {
              if let identifierType = inheritedType.type.as(IdentifierTypeSyntax.self) {
                MemberBlockItemSyntax(
                  decl: witnessVariableDecl(identifierType.name.text)
                )
              }
            }
          }

          for member in protocolDecl.memberBlock.members {
            if let member = processProtocolRequirement(member.decl) {
              member
            }
          }
        })
      )
    )

    return [
      DeclSyntax(structDecl)
    ]
  }

  static private func witnessVariableDecl(_ name: String) -> VariableDeclSyntax {
    VariableDeclSyntax(
      bindingSpecifier: .keyword(.let),
      bindings: PatternBindingListSyntax(
        itemsBuilder: {
          PatternBindingListSyntax.Element(
            pattern: IdentifierPatternSyntax(
              identifier: "\(raw: name.lowercaseFirst())"
            ),
            typeAnnotation: witnessTypeNamed(name)
          )
        }
      )
    )
  }

  static private func witnessTypeNamed(_ name: String) -> TypeAnnotationSyntax {
    TypeAnnotationSyntax(
      type: IdentifierTypeSyntax(
        name: "\(raw: name)Witness",
        genericArgumentClause: GenericArgumentClauseSyntax(
          arguments: GenericArgumentListSyntax(
            arrayLiteral: GenericArgumentSyntax(
              argument: IdentifierTypeSyntax(
                name: TokenSyntax(stringLiteral: Self.genericLabel)
              )
            )
          )
        )
      )
    )
  }

  static private func processProtocolRequirement(_ decl: DeclSyntax) -> MemberBlockItemSyntax? {
    if let functionDecl = decl.as(FunctionDeclSyntax.self) {
      return MemberBlockItemSyntax(
        decl: VariableDeclSyntax(
          bindingSpecifier: .keyword(.let),
          bindings: PatternBindingListSyntax(
            itemsBuilder: {
              PatternBindingListSyntax.Element(
                pattern: IdentifierPatternSyntax(
                  identifier: functionDecl.name
                ),
                typeAnnotation: TypeAnnotationSyntax(
                  type: functionRequirementWitnessType(functionDecl))
              )
            }
          )
        )
      )
    } else if let variableDecl = decl.as(VariableDeclSyntax.self),
              let identifier = variableDecl.bindings.first?.pattern.as(IdentifierPatternSyntax.self) {
      return MemberBlockItemSyntax(
        decl: VariableDeclSyntax(
          bindingSpecifier: .keyword(.let),
          bindings: PatternBindingListSyntax(
            itemsBuilder: {
              PatternBindingListSyntax.Element(
                pattern: identifier,
                typeAnnotation: TypeAnnotationSyntax(
                  type: variableRequirementWitnessType(variableDecl))
              )
            }
          )
        )
      )
    } else if let associatedTypeDecl = decl.as(AssociatedTypeDeclSyntax.self) {

      for inheritedType in associatedTypeDecl.inheritanceClause?.inheritedTypes ?? [] {
        guard let identifierType = inheritedType.type.as(IdentifierTypeSyntax.self) else {
          continue
        }

        return MemberBlockItemSyntax(decl: witnessVariableDecl(identifierType.name.text))
      }
    }

    return nil
  }

  
  /// The type of the property created when de-protocolizing a protocol function requirement
  static private func variableRequirementWitnessType(_ variableDecl: VariableDeclSyntax) -> FunctionTypeSyntax  {

    return FunctionTypeSyntax(
      parameters: TupleTypeElementListSyntax(itemsBuilder: {
       if variableDecl.modifiers.contains(where: { $0.name.text == TokenSyntax.keyword(.static).text}) {
          //Do not add instance param if method is static
        } else {
          // Instance reference
          selfTupleTypeElement()
        }
      }), returnClause: ReturnClauseSyntax(
        type: Self.replaceSelf(typeSyntax: variableDecl.bindings.first?.typeAnnotation?.type ?? TypeSyntax(stringLiteral: "Void"))))
  }

  /// The type of the property created when de-protocolizing a protocol function  requirement
  static private func functionRequirementWitnessType(_ functionDecl: FunctionDeclSyntax) -> FunctionTypeSyntax  {
    FunctionTypeSyntax(
      parameters: TupleTypeElementListSyntax(itemsBuilder: {
        // Convert mutating to inout
        if functionDecl.modifiers.contains(where: { $0.name.text == TokenSyntax.keyword(.mutating).text}) {
          inoutSelfTupleTypeElement()
        } else if functionDecl.modifiers.contains(where: { $0.name.text == TokenSyntax.keyword(.static).text}) {
          //Do not add instance param if method is static
        } else {
          // Instance reference
          selfTupleTypeElement()
        }

        // Protocol requirement parameters
        for parameter in functionDecl.signature.parameterClause.parameters {
          if let identifierType = parameter.type.as(IdentifierTypeSyntax.self), identifierType.name.text == "Self" {
            selfTupleTypeElement()
          } else {
            TupleTypeElementSyntax(type: parameter.type)
          }
        }
      }), returnClause: ReturnClauseSyntax(
        type: Self.replaceSelf(typeSyntax: functionDecl.signature.returnClause?.type ?? TypeSyntax(stringLiteral: "Void"))))
  }

  static func inoutSelfTupleTypeElement() -> TupleTypeElementSyntax {
    TupleTypeElementSyntax(
      type:  AttributedTypeSyntax(
        specifier: .keyword(.inout),
        baseType: IdentifierTypeSyntax(
          name: TokenSyntax(stringLiteral: Self.genericLabel)
        )
      )
    )
  }

  static func selfTupleTypeElement() -> TupleTypeElementSyntax {
    TupleTypeElementSyntax(
      type: IdentifierTypeSyntax(
        name: TokenSyntax(stringLiteral: Self.genericLabel)
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
  
  static func genericParameterClause(_ protocolDecl: ProtocolDeclSyntax) -> GenericParameterClauseSyntax? {
    let nonPrimary = associatedTypeToGenericParam(protocolDecl, primary: false)
    let primary = associatedTypeToGenericParam(protocolDecl, primary: true)

    let parameters = GenericParameterListSyntax(itemsBuilder: {
      GenericParameterSyntax(name: TokenSyntax(stringLiteral: Self.genericLabel))

      for parameter in primary {
        parameter
      }

      for parameter in nonPrimary {
        parameter
          .with(\.inheritedType, nil)
          .with(\.colon, nil)
      }
    })

    return GenericParameterClauseSyntax(parameters: parameters)
  }
  
  static func associatedTypeToGenericParam(_ protocolDecl: ProtocolDeclSyntax, primary: Bool) -> [GenericParameterSyntax] {
    let primaryAssociatedTypeNames = protocolDecl.primaryAssociatedTypeClause?.primaryAssociatedTypes

    let associatedTypes: [GenericParameterSyntax] = protocolDecl.memberBlock.members
      .compactMap({ member in
        guard let associatedType = member.decl.as(AssociatedTypeDeclSyntax.self) else {
          return nil
        }

        let isPrimary = primaryAssociatedTypeNames?.contains(where: { $0.name.description == associatedType.name.description }) ?? false

        let inheritedTypes = associatedType.inheritanceClause?.inheritedTypes.compactMap({ $0.type.as(IdentifierTypeSyntax.self) }) ?? []
        let inheritedType = inheritedTypes.first

        let genericParam = GenericParameterSyntax(name: associatedType.name,
                                                  colon: inheritedType != nil ? .colonToken() : nil,
                                                  inheritedType: inheritedType)
        if primary {
          return isPrimary ? genericParam : nil
        } else {
          return isPrimary ? nil : genericParam
        }
      })

    return associatedTypes
  }

}

extension String {
    func lowercaseFirst() -> String {
        guard let firstLetter = self.first else { return self }

        // Check if the first letter is already lowercase
        if firstLetter.isLowercase {
            return self
        }

        // Convert the first letter to lowercase and concatenate with the rest of the string
        return firstLetter.lowercased() + self.dropFirst()
    }
}
