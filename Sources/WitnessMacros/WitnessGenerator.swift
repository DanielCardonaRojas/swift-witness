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
    let convertedProtocolRequirements: [MemberBlockItemSyntax] = protocolDecl.memberBlock.members.compactMap { member in
      if let member = processProtocolRequirement(member.decl) {
        return member
      }
      return nil
    }

    // 2) Create the extension(s) for map/pullback/iso
    let variances = witnessStructVariance(protocolDecl)
    let utilityMethods = generateUtilityExtensions(protocolDecl, variances: variances)

    let structDecl = StructDeclSyntax(
      modifiers: .init(itemsBuilder: {
        DeclModifierSyntax(name: .keyword(.public))
      }),
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

          for member in convertedProtocolRequirements {
            member
          }

          // Initializers
          witnessDefaultInit(protocolDecl)
          if containsOption("conformanceInit", protocolDecl: protocolDecl) {
            witnessConformanceInit(protocolDecl)
          }

          // Utilities
          if containsOption("utilities", protocolDecl: protocolDecl) {
            for utilityMethod in utilityMethods {
              utilityMethod
            }
          }
        })
      )
    )

    return [DeclSyntax(structDecl)]
  }

  static func containsOption(_ option: String, protocolDecl: ProtocolDeclSyntax) -> Bool {
    let attribute = protocolDecl.attributes.first(where: { attribute in
      guard let attr = attribute.as(AttributeSyntax.self) else {
        return false
      }

      guard let arguments = attr.arguments?.as(LabeledExprListSyntax.self) else {
        // No arguments or unexpected format
        return false
      }

      let hasConformance = arguments.contains(where: { element in
        element.expression.description.contains(option)
      })

      return hasConformance
    })

    return attribute != nil
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

  // MARK: Initializers
  static func witnessDefaultInit(_ protocolDecl: ProtocolDeclSyntax) -> InitializerDeclSyntax {
    .init(
      modifiers: .init(itemsBuilder: {
        DeclModifierSyntax(name: .keyword(.public))
      }),
      signature: .init(
        parameterClause: defaultInitializerParameters(protocolDecl)
      ),
      body: .init(statementsBuilder: {
        for name in requirementNames(protocolDecl) {
          InfixOperatorExprSyntax(
            leftOperand: MemberAccessExprSyntax(
              base: DeclReferenceExprSyntax(baseName: .identifier("self")),
              declName: DeclReferenceExprSyntax(baseName: name)
            ),
            operator: AssignmentExprSyntax(),
            rightOperand: DeclReferenceExprSyntax(baseName: name)
          )
        }
      })
    )
  }


  /// Creates a witness from a type that conforms to the protocol that the witness represents
  static func associatedTypes(_ protocolDecl: ProtocolDeclSyntax) -> [AssociatedTypeDeclSyntax] {
    protocolDecl.memberBlock.members.compactMap({ $0.decl.as(AssociatedTypeDeclSyntax.self) })
  }

  static func witnessConformanceInit(_ protocolDecl: ProtocolDeclSyntax) -> InitializerDeclSyntax {
    // init() where Self: <Protocol>, AssociatedType: <Constraint> ...
    .init(
      modifiers: .init(itemsBuilder: {
        DeclModifierSyntax(name: .keyword(.public))
      }),
      signature: .init(parameterClause: .init(parametersBuilder: {})),
      genericWhereClause: .init(
        requirements: .init(
          itemsBuilder: {
            GenericRequirementSyntax(
              requirement: .conformanceRequirement(
                .init(
                  leftType: IdentifierTypeSyntax(
                    name: .identifier(Self.genericLabel)
                  ),
                  rightType: IdentifierTypeSyntax(
                    name: protocolDecl.name
                  )
                )
              )
            )

            // Constraints for associated types
            for associatedType in associatedTypes(protocolDecl) {
              if let constraints = associatedType.inheritanceClause?.inheritedTypes {
                for constraint in constraints {
                  if let identifier = constraint.type.as(IdentifierTypeSyntax.self) {
                    GenericRequirementSyntax(
                      requirement: .conformanceRequirement(
                        .init(
                          leftType: IdentifierTypeSyntax(name: associatedType.name),
                          rightType: identifier
                        )
                      )
                    )

                    GenericRequirementSyntax(
                      requirement: .sameTypeRequirement(
                        .init(
                          leftType: IdentifierTypeSyntax(
                            name: .identifier("\(Self.genericLabel).\(associatedType.name.text)")
                          ),
                          equal: .binaryOperator("=="),
                          rightType: IdentifierTypeSyntax(name: associatedType.name)
                        )
                      )
                    )
                  }
                }
              }
            }
          }
        )
      ),
      body: .init(statementsBuilder: {
        for (name, isStatic, kind, parameters) in requirements(protocolDecl) {
          if kind == .witness {
            InfixOperatorExprSyntax(
              leftOperand: MemberAccessExprSyntax(
                base: DeclReferenceExprSyntax(baseName: .identifier("self")),
                declName: DeclReferenceExprSyntax(baseName: name)
              ),
              operator: AssignmentExprSyntax(),
              rightOperand:
                FunctionCallExprSyntax.init(
                  calledExpression: MemberAccessExprSyntax(period: .periodToken(), name: .identifier("init")),
                  leftParen: .leftParenToken(),
                  arguments: .init(),
                  rightParen: .rightParenToken()
                )
            )

          } else {
            InfixOperatorExprSyntax(
              leftOperand: MemberAccessExprSyntax(
                base: DeclReferenceExprSyntax(baseName: .identifier("self")),
                declName: DeclReferenceExprSyntax(baseName: name)
              ),
              operator: AssignmentExprSyntax(),
              rightOperand:
                conformanceInitializerClosureImplementations(
                  name: name,
                  isStatic: isStatic,
                  kind: kind,
                  parameters: parameters
                )
            )

          }
        }
      })
    )
  }

  static func conformanceInitializerClosureImplementations(
    name: TokenSyntax,
    isStatic: Bool,
    kind: RequirementKind,
    parameters: [FunctionParameterSyntax]
  ) -> ClosureExprSyntax {
    ClosureExprSyntax(
              signature: isStatic && parameters.isEmpty ? nil : ClosureSignatureSyntax(
                parameterClause: ClosureSignatureSyntax
                  .ParameterClause(
                  ClosureShorthandParameterListSyntax(
                    itemsBuilder: {
                      if !isStatic {
                        ClosureShorthandParameterSyntax(name: .identifier("instance"))
                      }

                      for parameter in parameters {
                        ClosureShorthandParameterSyntax(name: parameter.secondName ?? parameter.firstName)
                      }
                    }
                  )
                )
              ),
              statements: CodeBlockItemListSyntax(
                itemsBuilder: {
                  if kind == .function {
                    FunctionCallExprSyntax.init(
                      calledExpression: MemberAccessExprSyntax.init(
                        base: DeclReferenceExprSyntax(baseName: .identifier(isStatic ? Self.genericLabel : "instance")),
                        declName: DeclReferenceExprSyntax(baseName: name)
                      ),
                      leftParen: .leftParenToken(),
                      rightParen: .rightParenToken(),
                      argumentsBuilder: {
                        for parameter in parameters {
                          LabeledExprSyntax(
                            label: parameter.firstName,
                            colon: .colonToken(),
                            expression: DeclReferenceExprSyntax(
                              baseName: parameter.secondName ?? parameter.firstName
                            )
                          )
                        }
                      }
                    )
                  } else {
                    MemberAccessExprSyntax.init(
                      base: DeclReferenceExprSyntax(baseName: .identifier(isStatic ? Self.genericLabel : "instance")),
                      declName: DeclReferenceExprSyntax(baseName: name)
                    )
                  }
                }
              )
            )
  }


  // MARK: Deprotocolization

  static func witnessStructName(_ protocolDecl: ProtocolDeclSyntax) -> TokenSyntax {
    "\(raw: protocolDecl.name.text)Witness"
  }

  static private func witnessVariableDecl(_ name: String, genericTypeName: String? = nil) -> VariableDeclSyntax {
    VariableDeclSyntax(
      modifiers: .init(itemsBuilder: {
        DeclModifierSyntax(name: .keyword(.public))
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

  /// Creates a type with the form <MyProtocolName>Witness<GENERIC_TYPE_NAME> e.g: DiffableWitness<Format>
  static private func witnessTypeNamed(_ name: String, genericTypeName: String? = nil) -> IdentifierTypeSyntax {
    IdentifierTypeSyntax(
      name: "\(raw: name)Witness",
      genericArgumentClause: GenericArgumentClauseSyntax(
        arguments: GenericArgumentListSyntax(
          arrayLiteral: GenericArgumentSyntax(
            argument: IdentifierTypeSyntax(
              name: TokenSyntax(stringLiteral: genericTypeName ?? Self.genericLabel)
            )
          )
        )
      )
    )
  }

  /// Determines if the generated witness struct need a pullback, map or iso method.
  /// if the set contains a covariant and contravariant then an iso is required
  /// if the set contains covariant and not contravariant then a map is required
  /// if the set contains a contravariant and not a covariant then a pullback is required
  static private func witnessStructVariance(_ protocolDecl: ProtocolDeclSyntax) -> Set<Variance> {
    let generics = associatedTypeToGenericParam(protocolDecl, primary: nil)
    let variances: [Variance] = protocolDecl.memberBlock.members.compactMap { member in
      guard let functionDecl = member.decl.as(FunctionDeclSyntax.self) else {
        return nil
      }
      return variance(functionSignature: functionDecl.signature, generics: generics)
    }

    return Set(variances)
  }

  static private func defaultInitializerParameters(_ protocolDecl: ProtocolDeclSyntax) -> FunctionParameterClauseSyntax {
    let parameters = protocolDecl.memberBlock.members.flatMap(
{ (member: MemberBlockItemSyntax) -> [FunctionParameterSyntax] in
      let decl = member.decl
      if let functionDecl = decl.as(FunctionDeclSyntax.self) {
        return [FunctionParameterSyntax(
          firstName: functionDecl.name,
          type: AttributedTypeSyntax(
            specifiers: .init(itemsBuilder: {}),
            attributes: .init(itemsBuilder: {
              AttributeSyntax(
                atSign: .atSignToken(),
                attributeName: IdentifierTypeSyntax(name: .identifier("escaping"))
              )
            }),
            baseType: functionRequirementWitnessType(functionDecl)
          )
        )]
      } else if let variableDecl = decl.as(VariableDeclSyntax.self),
                let identifier = variableDecl.bindings.first?.pattern.as(IdentifierPatternSyntax.self) {
        return [FunctionParameterSyntax(
          firstName: identifier.identifier,
          type: AttributedTypeSyntax(
            specifiers: .init(itemsBuilder: {}),
            attributes: .init(itemsBuilder: {
              AttributeSyntax(
                atSign: .atSignToken(),
                attributeName: IdentifierTypeSyntax(name: .identifier("escaping"))
              )
            }),
            baseType: variableRequirementWitnessType(variableDecl)
          )
        )]
      } else if let associatedTypeDecl = decl.as(AssociatedTypeDeclSyntax.self) {

        return (associatedTypeDecl.inheritanceClause?.inheritedTypes ?? [])
          .flatMap(
            { (inheritedType: InheritedTypeListSyntax.Element) -> [FunctionParameterSyntax] in
              guard let identifierType = inheritedType.type.as(IdentifierTypeSyntax.self) else {
                return []
              }

              let name = identifierType.name.text
              return [FunctionParameterSyntax(
                firstName: .init(stringLiteral: name.lowercaseFirst()),
                type: witnessTypeNamed(
                  name,
                  genericTypeName: associatedTypeDecl.name.text
                )
              )]
            })
      } else {
        return []
      }
})

    return .init(parametersBuilder: {
      for param in parameters {
        param
      }
    })
  }

  static private func processProtocolRequirement(_ decl: DeclSyntax) -> MemberBlockItemSyntax? {
    if let functionDecl = decl.as(FunctionDeclSyntax.self) {
      return MemberBlockItemSyntax(
        decl: VariableDeclSyntax(
          modifiers: .init(itemsBuilder: {
            DeclModifierSyntax(name: .keyword(.public))
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
            DeclModifierSyntax(name: .keyword(.public))
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
          decl: witnessVariableDecl(identifierType.name.text, genericTypeName: associatedTypeDecl.name.text)
        )
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
      type: AttributedTypeSyntax(
        specifiers: .init(itemsBuilder: {
          .init(specifier: .keyword(.inout))
        }),
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
  // MARK: Utility extensions
  static private func generateUtilityExtensions(
    _ protocolDecl: ProtocolDeclSyntax,
    variances: Set<Variance>
  ) -> [MemberBlockItemSyntax] {

    // The name of the witness struct we generated, e.g., `CombinableWitness`.
    let witnessName = witnessStructName(protocolDecl) // e.g. "CombinableWitness"

    // Collect extension members (the utility methods).
    var members = [MemberBlockItemSyntax]()

    // If we detect `.invariant` or a mix of covariant+contravariant, we typically want `iso`.
    if variances.contains(.invariant) ||
       (variances.contains(.contravariant) && variances.contains(.covariant)) {
      members.append(MemberBlockItemSyntax(decl: transformedWitness(semantic: .iso, protocolDecl: protocolDecl, witnessName: witnessName)))
    } else {
      // If strictly contravariant => generate pullback
      if variances.contains(.contravariant) {
        members.append(MemberBlockItemSyntax(decl: transformedWitness(semantic: .pullback, protocolDecl: protocolDecl, witnessName: witnessName)))
      }
      // If strictly covariant => generate map
      if variances.contains(.covariant) {
        members.append(MemberBlockItemSyntax(decl: transformedWitness(semantic: .map, protocolDecl: protocolDecl, witnessName: witnessName)))
      }
    }

    // If we ended up with no methods to generate, just return empty
    if members.isEmpty {
      return []
    }

    return members
  }

  /// Generates method transforming witness to another type
  /// ```swift
  /// extension <WitnessName> {
  ///   func pullback<B>(_ f: @escaping (B) -> A) -> <WitnessName><B> {
  ///     .init(combine: { b1, b2 in
  ///       self.combine(f(b1), f(b2))
  ///     })
  ///   }
  /// }
  /// ```
  /// or:
  /// ```swift
  /// extension <WitnessName> {
  ///   func map<B>(_ f: @escaping (A) -> B) -> <WitnessName><B> {
  ///     .init(combine: { a1, a2 in
  ///       let result = self.combine(a1, a2)
  ///       return f(result)
  ///     })
  ///   }
  /// }
  /// ```
  /// or:
  /// ```swift
  /// extension <WitnessName> {
  ///   func iso<B>(
  ///     _ pullback: @escaping (B) -> A,
  ///     map: @escaping (A) -> B
  ///   ) -> <WitnessName><B> {
  ///     .init(combine: { b1, b2 in
  ///       let r = self.combine(pullback(b1), pullback(b2))
  ///       return map(r)
  ///     })
  ///   }
  /// }
  /// ```
  static private func transformedWitness(
    semantic: TransformedWitnessSemantic,
    protocolDecl: ProtocolDeclSyntax,
    witnessName: TokenSyntax
  ) -> FunctionDeclSyntax {
    // `func iso<B>(_ pullback: @escaping (B) -> A, map: @escaping (A) -> B) -> <WitnessName><B>`
    FunctionDeclSyntax(
      name: .identifier(semantic.rawValue),
      genericParameterClause: GenericParameterClauseSyntax(
        parameters: GenericParameterListSyntax {
          GenericParameterSyntax(name: .identifier("B"))
        }
      ),
      signature: FunctionSignatureSyntax(
        parameterClause: FunctionParameterClauseSyntax {
          // ( _ pullback: @escaping (B) -> A )
          if semantic == .iso || semantic == .pullback {
            FunctionParameterSyntax(
              firstName: .identifier("pullback"),
              colon: .colonToken(),
              type: AttributedTypeSyntax(
                specifiers: .init(itemsBuilder: {

                }),
                attributes: .init(
                  itemsBuilder: {
                    AttributeSyntax(
                      atSign: .atSignToken(),
                      attributeName: IdentifierTypeSyntax(name: .identifier("escaping"))
                    )
                  }),
                baseType:
                  FunctionTypeSyntax(
                    parameters: TupleTypeElementListSyntax {
                      TupleTypeElementSyntax(
                        type: IdentifierTypeSyntax(name: .identifier("B"))
                      )
                    },
                    returnClause: ReturnClauseSyntax(
                      type: IdentifierTypeSyntax(name: .identifier(genericLabel))
                    )
                  )
              )
            )
          }
          // ( map: @escaping (A) -> B )
          if semantic == .iso || semantic == .map {
            FunctionParameterSyntax(
              firstName: .identifier("map"),
              colon: .colonToken(),
              type: AttributedTypeSyntax(
                specifiers: .init(itemsBuilder: {

                }),
                attributes: .init(
                  itemsBuilder: {
                    AttributeSyntax(
                      atSign: .atSignToken(),
                      attributeName: IdentifierTypeSyntax(name: .identifier("escaping"))
                    )
                  }),
                baseType: FunctionTypeSyntax(
                  parameters: TupleTypeElementListSyntax {
                    TupleTypeElementSyntax(
                      type: IdentifierTypeSyntax(name: .identifier(genericLabel))
                    )
                  },
                  returnClause: ReturnClauseSyntax(
                    type: IdentifierTypeSyntax(name: .identifier("B"))
                  )
                )
              )
            )
          }
        },
        returnClause: ReturnClauseSyntax(
          type: TypeSyntax(
            genericType(witnessName: witnessName, typeArg: "B")
          )
        )
      )
    ) {
      CodeBlockItemListSyntax {
        transformedInstance(protocolDecl)
      }
    }
  }

  static private func transformedInstance(_ protocolDecl: ProtocolDeclSyntax) -> FunctionCallExprSyntax {
    FunctionCallExprSyntax(
      calledExpression: MemberAccessExprSyntax(
        declName: DeclReferenceExprSyntax(
          baseName: .identifier("init")
        )
      ),
      leftParen: .leftParenToken(),
      arguments: .init(itemsBuilder: {
        for argument in constructorArguments(protocolDecl) {
          argument
        }
      }),
      rightParen: .rightParenToken()
    )

  }

  static private func constructorArguments(_ protocolDecl: ProtocolDeclSyntax) -> [LabeledExprSyntax] {
    // TODO: Transform witness variables
    protocolDecl.memberBlock.members
      .compactMap({
        guard let functionDecl = $0.decl.as(FunctionDeclSyntax.self) else {
          return nil
        }

        return LabeledExprSyntax(
          label: functionDecl.name,
          colon: .colonToken(),
          expression: transformedClosure(functionDecl, protocolDecl: protocolDecl))
      })
  }

  static private func transformedClosure(_ functionDecl: FunctionDeclSyntax, protocolDecl: ProtocolDeclSyntax) -> ClosureExprSyntax {
    let generics = associatedTypeToGenericParam(protocolDecl, primary: nil)
    let closureType = functionRequirementWitnessType(functionDecl)
    let closureCall = FunctionCallExprSyntax(
      calledExpression: MemberAccessExprSyntax(
        base: DeclReferenceExprSyntax(baseName: .identifier("self")),
        declName: DeclReferenceExprSyntax(baseName: functionDecl.name)
      ),
      leftParen: .leftParenToken(),
      rightParen: .rightParenToken(),
      argumentsBuilder: {
        // Rest of params
        for (index, parameter) in closureType.parameters.enumerated() {
          if varianceOf(parameter: parameter, generics: generics) == .invariant {
            LabeledExprSyntax(
              expression: FunctionCallExprSyntax(
                calledExpression: DeclReferenceExprSyntax(
                  baseName: .identifier("pullback")
                ),
                leftParen: .leftParenToken(),
                arguments: LabeledExprListSyntax(
                  arrayLiteral: .init(
                    expression: DeclReferenceExprSyntax(
                      baseName: .dollarIdentifier("$\(index)")
                    )
                  )
                ),
                rightParen: .rightParenToken()
              )
            )
          } else {
            LabeledExprListSyntax(
              arrayLiteral: .init(
                expression: DeclReferenceExprSyntax(
                  baseName: .dollarIdentifier("$\(index)")
                )
              )
            )
          }
        }
      }
    )

    let variance = variance(
      functionSignature: functionDecl.signature,
      generics: generics
    )

    // If contains Self in the return type then map the return value
    if variance == .covariant || variance == .invariant {
      return ClosureExprSyntax(
        signature: nil,
        statementsBuilder: {
          CodeBlockItemSyntax(
            item: .expr(
              ExprSyntax(
                FunctionCallExprSyntax(
                  calledExpression: DeclReferenceExprSyntax(
                    baseName: .identifier("map")
                  ),
                  leftParen: .leftParenToken(),
                  arguments: .init(
                    itemsBuilder: {
                      LabeledExprSyntax(expression: closureCall)
                      }
                  ),
                  rightParen: .rightParenToken()
                )
              )
            )
          )
        }
      )
    }

    // Does not have contain Self in the return type
    return ClosureExprSyntax(
      signature: nil,
      statementsBuilder: {
        CodeBlockItemSyntax(
          item: .expr(
            ExprSyntax(
              closureCall
            )
          )
        )
      }
    )
  }


  static private func functionTypes(_ protocolDecl: ProtocolDeclSyntax) -> [FunctionTypeSyntax] {
    protocolDecl.memberBlock.members.compactMap { member in
      let decl = member.decl
      if let functionDecl = decl.as(FunctionDeclSyntax.self) {
        return functionRequirementWitnessType(functionDecl)
      } else if let variableDecl = decl.as(VariableDeclSyntax.self),
                let identifier = variableDecl.bindings.first?.pattern.as(IdentifierPatternSyntax.self) {

        return variableRequirementWitnessType(variableDecl)
      }
      return nil
    }
  }

  // MARK: Helpers

  /// Helper to produce "<witnessName><B>"
  private static func genericType(witnessName: TokenSyntax, typeArg: String) -> some TypeSyntaxProtocol {
    return IdentifierTypeSyntax(
      name: witnessName,
      genericArgumentClause: GenericArgumentClauseSyntax(
        arguments: GenericArgumentListSyntax {
          GenericArgumentSyntax(argument: IdentifierTypeSyntax(name: .identifier(typeArg)))
        }
      )
    )
  }



  /// **Core method**: Determines the variance of a function signature by checking
  /// how the generic parameters are used in the function's parameter list (input)
  /// and return type (output).
  ///
  /// - Parameters:
  ///   - functionSignature: The syntax node describing the function signature.
  ///   - generics: The generic parameters (e.g., `T`, `U`) declared on the function.
  /// - Returns: A `Variance` value (`.contravariant`, `.covariant`, or `.invariant`).
  private static func variance(
      functionSignature: FunctionSignatureSyntax,
      generics: [GenericParameterSyntax]
  ) -> Variance {
      // 1) Collect the declared generic names: e.g., ["T", "U", ...]
      var declaredGenericNames = Set(generics.map { $0.name.text })
      declaredGenericNames.insert("Self")

      // 2) Collect generics used in parameter types (input position).
      //    We'll iterate through every parameter and walk its type syntax.
      var genericsInParams = Set<String>()
      for param in functionSignature.parameterClause.parameters {
          let paramType = param.type
          let collector = GenericNameCollector(declaredGenerics: declaredGenericNames)
          collector.walk(paramType)
          genericsInParams.formUnion(collector.foundGenerics)
      }

      // 3) Collect generics used in the return type (output position).
      var genericsInReturn = Set<String>()
      if let returnClause = functionSignature.returnClause {
          let returnType = returnClause.type
          let collector = GenericNameCollector(declaredGenerics: declaredGenericNames)
          collector.walk(returnType)
          genericsInReturn.formUnion(collector.foundGenerics)
      }

      // 4) Apply simple variance logic:
      //    - If any generic is in both input and output, => invariant
      //    - If generics are only in parameters => contravariant
      //    - If generics are only in return => covariant
      //    - Otherwise (e.g., none used at all) => invariant
      let intersection = genericsInParams.intersection(genericsInReturn)
      if !intersection.isEmpty {
          return .invariant
      } else if !genericsInParams.isEmpty && genericsInReturn.isEmpty {
          return .contravariant
      } else if genericsInParams.isEmpty && !genericsInReturn.isEmpty {
          return .covariant
      } else {
          // If no generics are found at all or any other fallback scenario:
          return .invariant
      }
  }

  static func varianceOf(
    parameter: TupleTypeElementSyntax,
    generics: [GenericParameterSyntax]
  ) -> Variance {
    var declaredGenericNames = Set(generics.map { $0.name.text })
    declaredGenericNames.insert("Self")
    let genericsInParamType = Set<String>()
    let collector = GenericNameCollector(declaredGenerics: declaredGenericNames)
    collector.walk(parameter)

    if !genericsInParamType.intersection(declaredGenericNames).isEmpty {
      return .contravariant
    }

    return .invariant
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


enum Variance: Equatable {
  case contravariant
  case covariant
  case invariant
}

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


extension FunctionDeclSyntax {
  func isModifiedWith(_ keyword: Keyword) -> Bool {
    modifiers.contains(where: { $0.name.text == TokenSyntax.keyword(keyword).text})
  }
}

extension VariableDeclSyntax {
  func isModifiedWith(_ keyword: Keyword) -> Bool {
    modifiers.contains(where: { $0.name.text == TokenSyntax.keyword(keyword).text})
  }
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
