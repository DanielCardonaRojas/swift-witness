//
//  WitnessGenerator+Initializers.swift
//  Witness
//
//  Created by Daniel Cardona on 8/01/25.
//

import SwiftSyntax
import SwiftSyntaxBuilder

/// Generates initializers for the witness
extension WitnessGenerator {

  /// Generates all the initializers for the witness struct.
  ///
  /// This includes the default initializer that takes closures for each protocol requirement,
  /// and optionally, a conformance-based initializer if the `.conformanceInit` option is specified.
  ///
  /// - Parameter protocolDecl: The protocol declaration to generate initializers for.
  /// - Returns: An array of `MemberBlockItemSyntax` containing the generated initializers.
    static func witnessInitializers(_ protocolDecl: ProtocolDeclSyntax, options: WitnessOptions?) -> [MemberBlockItemSyntax] {
    let options = options ?? codeGenOptions(protocolDecl: protocolDecl)
    var initializers = [MemberBlockItemSyntax]()
    initializers.append(MemberBlockItemSyntax(decl: witnessDefaultInit(protocolDecl)))
    if options?.contains(.conformanceInit) ?? false {
      initializers.append(MemberBlockItemSyntax(decl: witnessConformanceInit(protocolDecl)))
    }
    return initializers
  }

  /// Generates the default initializer for the witness struct.
  ///
  /// This initializer accepts a closure for each requirement of the protocol.
  ///
  /// For a protocol like:
  /// ```swift
  /// protocol Service {
  ///     func doSomething() -> String
  /// }
  /// ```
  /// This generates:
  /// ```swift
  /// init(doSomething: @escaping (A) -> String) {
  ///     self.doSomething = doSomething
  /// }
  /// ```
  static func witnessDefaultInit(_ protocolDecl: ProtocolDeclSyntax) -> InitializerDeclSyntax {
    .init(
      modifiers: .init(itemsBuilder: {
        if let modifier = accessModifier(protocolDecl) {
          modifier
        }
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

  /// Generates an initializer that creates a witness from a conforming type.
  ///
  /// This allows for easily creating a witness struct from an existing type that
  /// already conforms to the protocol.
  ///
  /// For a protocol `Service` and a conforming type `MyService`:
  /// ```swift
  /// struct MyService: Service {
  ///     func doSomething() -> String { "Hello" }
  /// }
  /// ```
  /// This generates an initializer that can be used like:
  /// ```swift
  /// let witness = ServiceWitness(MyService.self)
  /// ```
  static func witnessConformanceInit(_ protocolDecl: ProtocolDeclSyntax) -> InitializerDeclSyntax {
    // init() where Self: <Protocol>, AssociatedType: <Constraint> ...
    .init(
      modifiers: .init(itemsBuilder: {
        if let modifier = accessModifier(protocolDecl) {
          modifier
        }
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

            /// Constraints for associated types. For example `A: Snapshottable`
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

                  }
                }
              }

              /// For example: `A.Format == Format`
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

  /// Creates the closure implementation for a protocol requirement in the conformance-based initializer.
  ///
  /// This function generates a closure that calls the corresponding method or property on the conforming type.
  ///
  /// For a function `doSomething()` on a non-static requirement, this generates:
  /// ```swift
  /// { instance in instance.doSomething() }
  /// ```
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

  /// Generates the parameter clause for the default initializer.
  ///
  /// This function creates a `FunctionParameterSyntax` for each requirement in the protocol,
  /// which is then used to construct the default initializer's signature.
  ///
  /// For a protocol with a function `doSomething() -> String`, this generates:
  /// ```swift
  /// doSomething: @escaping (A) -> String
  /// ```
  static func defaultInitializerParameters(_ protocolDecl: ProtocolDeclSyntax) -> FunctionParameterClauseSyntax {
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
      }
      else if let subscriptDecl = decl.as(SubscriptDeclSyntax.self) {
        return [FunctionParameterSyntax(
          firstName: .init(stringLiteral: "indexedBy"),
          type: AttributedTypeSyntax(
            specifiers: .init(itemsBuilder: {}),
            attributes: .init(itemsBuilder: {
              AttributeSyntax(
                atSign: .atSignToken(),
                attributeName: IdentifierTypeSyntax(name: .identifier("escaping"))
              )
            }),
            baseType: subscriptRequirementWitnessType(subscriptDecl)
          )
        )]
      }
      else if let variableDecl = decl.as(VariableDeclSyntax.self),
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

    return .init(
      parametersBuilder: {
        for (index, param) in parameters.enumerated() {
          if index == parameters.count - 1 {
            param
              .with(\.leadingTrivia, .newline)
              .with(\.trailingTrivia, .newline)
          } else {
            param.with(\.leadingTrivia, .newline)
          }
        }
      }
    )
  }
}
