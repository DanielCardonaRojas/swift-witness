//
//  WitnessGenerator.swift
//
//
//  Created by Daniel Cardona on 27/03/24.
//

import SwiftSyntax
import SwiftSyntaxBuilder
@_exported import WitnessTypes

public struct MacroError: Error {
    public let message: String
    public init(message: String) {
        self.message = message
    }
}

public enum WitnessGenerator {
  static let genericLabel = "A"

    public static func processProtocol(protocolDecl: ProtocolDeclSyntax, options: WitnessOptions? = nil) throws -> [DeclSyntax] {
    let options = options ?? codeGenOptions(protocolDecl: protocolDecl)
    let convertedProtocolRequirements: [MemberBlockItemSyntax] = protocolDecl.memberBlock.members.compactMap { member in
      if let member = processProtocolRequirement(
        member.decl,
        accessModifier: accessModifier(protocolDecl)
      ) {
        return member
      }
      return nil
    }

    var structDecl = StructDeclSyntax(
      modifiers: .init(itemsBuilder: {
        if let modifier = accessModifier(protocolDecl) {
          modifier
        }
      }),
      name: "\(raw: protocolDecl.name.text)Witness",
      genericParameterClause: genericParameterClause(protocolDecl),
      memberBlock: MemberBlockSyntax(
        members: MemberBlockItemListSyntax(itemsBuilder: {
          // Closure properties for method and variable requirements
          for member in groupedDeclarations(convertedProtocolRequirements)  {
            member
          }

          // Initializers
          for member in groupedDeclarations(witnessInitializers(protocolDecl, options: options), separated: true) {
            member
          }

          // Utilities
          if options?.contains(.utilities) ?? false {
            if let member = witnessTransformation(protocolDecl) {
              member
            }
          }

          // ErasableWitness conformance and erased() method
          if options?.contains(.erasable) ?? false {
            MemberBlockItemSyntax(decl: erasedFunctionDecl(protocolDecl))
          }
            // Table based Synthesized conformance
            if options?.contains(.synthesizedByTableConformance) ?? false {
              if let synthesizedConformance = try? Self.generateSynthesizedByTableConformance(protocolDecl: protocolDecl) {
                  MemberBlockItemSyntax(decl: synthesizedConformance)
              }
            }

          // Synthesized conformance
          if options?.contains(.synthesizedConformance) ?? false {
            if let synthesizedConformance = try? Self.generateSynthesizedConformance(protocolDecl: protocolDecl) {
                MemberBlockItemSyntax(decl: synthesizedConformance)
            }
          }
        })
      )
    )

    // Conditionally add ErasableWitness and RecordableMixin conformance
    var inherited: [String] = []
    if options?.contains(.synthesizedByTableConformance) ?? false {
        inherited.append("ErasableWitness")
    }
    if options?.contains(.synthesizedConformance) ?? false {
        inherited.append("RecordableMixin")
    }

    if !inherited.isEmpty {
        structDecl.inheritanceClause = InheritanceClauseSyntax(
            inheritedTypes: InheritedTypeListSyntax {
                for typeName in inherited {
                    InheritedTypeSyntax(type: IdentifierTypeSyntax(name: .identifier(typeName)))
                }
            }
        )
    }

    return [DeclSyntax(structDecl)]
  }


  static func requirementNames(_ protocolDecl: ProtocolDeclSyntax) -> [TokenSyntax] {
    requirements(protocolDecl).map(\.name)
  }

  /// returns a spec for the requirements of a protocol `name` of the function or variable
  static func requirements(_ protocolDecl: ProtocolDeclSyntax) -> [(name: TokenSyntax, static: Bool, kind: RequirementKind, parameters: [FunctionParameterSyntax])] {
    let requirementsArray = protocolDecl.memberBlock.members.flatMap(
      { (member: MemberBlockItemSyntax) -> [(name: TokenSyntax, static: Bool, kind: RequirementKind, parameters: [FunctionParameterSyntax])] in
      let decl = member.decl

      if let functionDecl = decl.as(FunctionDeclSyntax.self) {
        let parameters = functionDecl.signature.parameterClause.parameters.map({ $0 })
        return [(
          name: functionDecl.name,
          static: functionDecl.isModifiedWith(.static),
          kind: .function,
          parameters: parameters
        )]
      }

        if let subscriptDecl = decl.as(SubscriptDeclSyntax.self) {
          let parameters = subscriptDecl.parameterClause.parameters.map({ $0 })
          return [(
            name: .init(stringLiteral: "indexedBy"),
            static: subscriptDecl.isModifiedWith(.static),
            kind: .function,
            parameters: parameters
          )]
        }

      if let variableDecl = decl.as(VariableDeclSyntax.self),
          let identifier = variableDecl.bindings.first?.pattern.as(IdentifierPatternSyntax.self) {
        return [(identifier.identifier, variableDecl.isModifiedWith(.static), .variable, [])]
      }

      if let associatedTypeDecl = decl.as(AssociatedTypeDeclSyntax.self) {
        return (associatedTypeDecl.inheritanceClause?.inheritedTypes ?? [])
          .flatMap { (inheritedType: InheritedTypeListSyntax.Element) -> [(name: TokenSyntax, static: Bool, kind: RequirementKind, parameters: [FunctionParameterSyntax])]  in
          guard let identifierType = inheritedType.type.as(IdentifierTypeSyntax.self) else {
            return []
          }

          return [(
            name: .init(stringLiteral: identifierType.name.text.lowercaseFirst()),
            static: false,
            kind: .witness,
            parameters: []
          )]
        }
      }
      return []
    })

    return requirementsArray
  }

  /// Generates a variable for other witness dependencies
  /// If an associated type is constrained to another protocol then we must have a witness for that protocol as well. This method will create such variable.
  static private func witnessVariableDecl(
    _ name: String,
    genericTypeName: String? = nil,
    accessModifier: DeclModifierSyntax?
  ) -> VariableDeclSyntax {
    VariableDeclSyntax(
      modifiers: .init(itemsBuilder: {
        if let accessModifier {
          accessModifier
        }
      }),
      bindingSpecifier: .keyword(.let),
      bindings: PatternBindingListSyntax(
        itemsBuilder: {
          PatternBindingListSyntax.Element(
            pattern: IdentifierPatternSyntax(
              identifier: "\(raw: name.lowercaseFirst())"
            ),
            typeAnnotation: TypeAnnotationSyntax(
              type: witnessTypeNamed(name, genericTypeName: genericTypeName)
            )
          )
        }
      )
    )
  }

  /// Runs through all  protocol requirements and maps them into closure properties.
  static private func processProtocolRequirement(_ decl: DeclSyntax, accessModifier: DeclModifierSyntax?) -> MemberBlockItemSyntax? {
    if let functionDecl = decl.as(FunctionDeclSyntax.self) {
      return MemberBlockItemSyntax(
        decl: VariableDeclSyntax(
          modifiers: .init(itemsBuilder: {
            if let accessModifier {
              accessModifier
            }
          }),
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
          modifiers: .init(itemsBuilder: {
            if let accessModifier {
              accessModifier
            }
          }),
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

        return MemberBlockItemSyntax(
          decl: witnessVariableDecl(
            identifierType.name.text,
            genericTypeName: associatedTypeDecl.name.text,
            accessModifier: accessModifier
          )
        )
      }
    } else if let subscriptDecl = decl.as(SubscriptDeclSyntax.self) {
      return MemberBlockItemSyntax(
        decl: VariableDeclSyntax(
          modifiers: .init(itemsBuilder: {
            if let accessModifier {
              accessModifier
            }
          }),
          bindingSpecifier: .keyword(.let),
          bindings: PatternBindingListSyntax(
            itemsBuilder: {
              PatternBindingListSyntax.Element(
                pattern: IdentifierPatternSyntax(
                  identifier: .init(stringLiteral: "indexedBy")
                ),
                typeAnnotation: TypeAnnotationSyntax(
                  type: subscriptRequirementWitnessType(subscriptDecl))
              )
            }
          )
        )
      )

    }

    return nil
  }

  
  /// The type of the property created when de-protocolizing a protocol function requirement
  static func variableRequirementWitnessType(_ variableDecl: VariableDeclSyntax) -> FunctionTypeSyntax  {

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
  static func functionRequirementWitnessType(_ functionDecl: FunctionDeclSyntax) -> FunctionTypeSyntax  {
    let funcGenerics = functionDecl.genericParameterClause?.parameters

    class GenericReplacer: SyntaxRewriter {
        let generics: GenericParameterListSyntax?
        init(generics: GenericParameterListSyntax?) {
            self.generics = generics
        }
        override func visit(_ node: IdentifierTypeSyntax) -> TypeSyntax {
            if let generics, let genericParam = generics.first(where: { $0.name.text == node.name.text }) {
                if let constraint = genericParam.inheritedType {
                    return TypeSyntax(stringLiteral: "any \(constraint.trimmedDescription)")
                } else {
                    return TypeSyntax("Any")
                }
            }
            return super.visit(node)
        }
    }

    let rewriter = GenericReplacer(generics: funcGenerics)

    return FunctionTypeSyntax(
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
            let newType = TypeSyntax(rewriter.visit(parameter.type)) ?? parameter.type
            TupleTypeElementSyntax(type: newType)
          }
        }
      }),
      effectSpecifiers: functionDecl.signature.effectSpecifiers?.typeEffectSpecifiers(),
      returnClause: ReturnClauseSyntax(
        type: TypeSyntax(rewriter.visit(Self.replaceSelf(typeSyntax: functionDecl.signature.returnClause?.type ?? TypeSyntax(stringLiteral: "Void")))) ?? TypeSyntax(stringLiteral: "Void")
      )
    )
  }

  /// The type of the property created when de-protocolizing a protocol subscript requirement
  static func subscriptRequirementWitnessType(_ functionDecl: SubscriptDeclSyntax) -> FunctionTypeSyntax  {
    FunctionTypeSyntax(
      parameters: TupleTypeElementListSyntax(itemsBuilder: {
        if functionDecl.modifiers.contains(where: { $0.name.text == TokenSyntax.keyword(.static).text}) {
          //Do not add instance param if method is static
        } else {
          // Instance reference
          selfTupleTypeElement()
        }

        // Protocol requirement parameters
        for parameter in functionDecl.parameterClause.parameters {
          if let identifierType = parameter.type.as(IdentifierTypeSyntax.self), identifierType.name.text == "Self" {
            selfTupleTypeElement()
          } else {
            TupleTypeElementSyntax(type: parameter.type)
          }
        }
      }),
      returnClause: ReturnClauseSyntax(
        type: Self.replaceSelf(typeSyntax: functionDecl.returnClause.type)
      )
    )
  }

  /// Determines the generics that the witness struct will contain
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
  
  /// Returns the a list of generic types that the witness struct should include.
  ///  - Parameter primary: Nil if you want all generic types no matter if they are primary or not.
  static func associatedTypeToGenericParam(_ protocolDecl: ProtocolDeclSyntax, primary: Bool?) -> [GenericParameterSyntax] {
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
        if let primary, primary {
          return isPrimary ? genericParam : nil
        } else if let primary, !primary {
          return isPrimary ? nil : genericParam
        } else {
          return genericParam
        }
      })

    return associatedTypes
  }

  static private func functionTypes(_ protocolDecl: ProtocolDeclSyntax) -> [FunctionTypeSyntax] {
    protocolDecl.memberBlock.members.compactMap { member in
      let decl = member.decl
      if let functionDecl = decl.as(FunctionDeclSyntax.self) {
        return functionRequirementWitnessType(functionDecl)
      }
      else if let variableDecl = decl.as(VariableDeclSyntax.self),
              let _ = variableDecl.bindings.first?.pattern.as(IdentifierPatternSyntax.self) {

        return variableRequirementWitnessType(variableDecl)
      }
      return nil
    }
  }
}

