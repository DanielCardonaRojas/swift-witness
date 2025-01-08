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
}
