//
//  WitnessGenerator+Erased.swift
//  Witness
//
//  Created by Daniel Cardona on 2/07/25.
//
import SwiftSyntax


extension WitnessGenerator {
    /// Generates the `erased()` method for the witness struct.
    static func erasedFunctionDecl(_ protocolDecl: ProtocolDeclSyntax) -> FunctionDeclSyntax {
        let witnessName = witnessStructName(protocolDecl)
        let access = accessModifier(protocolDecl)

        let variances = witnessStructVariance(protocolDecl)
        let semantics = transformSemantics(from: variances)

        return FunctionDeclSyntax(
            modifiers: .init(itemsBuilder: {
                if let access { access }
            }),
            name: .identifier("erased"),
            signature: FunctionSignatureSyntax(
                parameterClause: FunctionParameterClauseSyntax(parameters: FunctionParameterListSyntax()),
                returnClause: ReturnClauseSyntax(
                    type: genericType(
                        witnessName: witnessName,
                        genericArgumentClause: GenericArgumentClauseSyntax(
                            arguments: GenericArgumentListSyntax {
                                GenericArgumentSyntax(argument: IdentifierTypeSyntax(name: .identifier("Any")))
                            }
                        )
                    )
                )
            ),
            body: CodeBlockSyntax(
                statements: CodeBlockItemListSyntax {
                    FunctionCallExprSyntax(
                        calledExpression: DeclReferenceExprSyntax(baseName: .identifier("transform")),
                        leftParen: .leftParenToken(),
                        arguments: LabeledExprListSyntax {
                            if semantics == .iso || semantics == .pullback {
                                LabeledExprSyntax(
                                    label: .identifier("pullback"),
                                    colon: .colonToken(),
                                    expression: ClosureExprSyntax(
                                        signature: ClosureSignatureSyntax(
                                            parameterClause: ClosureSignatureSyntax.ParameterClause.simpleInput(
                                                ClosureShorthandParameterListSyntax {
                                                    ClosureShorthandParameterSyntax(name: .identifier("instance"))
                                                }
                                            )
                                        ),
                                        statements: CodeBlockItemListSyntax {
                                            CodeBlockItemSyntax(
                                                item: .expr(
                                                    ExprSyntax(
                                                        AsExprSyntax(
                                                            expression: DeclReferenceExprSyntax(baseName: .identifier("instance")),
                                                            asKeyword: .keyword(.as),
                                                            questionOrExclamationMark: .exclamationMarkToken(),
                                                            type: IdentifierTypeSyntax(name: .identifier(Self.genericLabel))
                                                        )
                                                    )
                                                )
                                            )
                                        }
                                    )
                                )
                            }
                            if semantics == .iso || semantics == .map {
                                LabeledExprSyntax(
                                    label: .identifier("map"),
                                    colon: .colonToken(),
                                    expression: ClosureExprSyntax(
                                        signature: ClosureSignatureSyntax(
                                            parameterClause: ClosureSignatureSyntax.ParameterClause.simpleInput(
                                                ClosureShorthandParameterListSyntax {
                                                    ClosureShorthandParameterSyntax(name: .identifier("instance"))
                                                }
                                            )
                                        ),
                                        statements: CodeBlockItemListSyntax {
                                            CodeBlockItemSyntax(
                                                item: .expr(
                                                    ExprSyntax(
                                                        DeclReferenceExprSyntax(baseName: .identifier("instance"))
                                                    )
                                                )
                                            )
                                        }
                                    )
                                )
                            }
                        },
                        rightParen: .rightParenToken()
                    )
                }
            )
        )
    }
}
