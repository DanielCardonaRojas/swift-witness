import SwiftSyntax
import SwiftSyntaxBuilder
import WitnessTypes

extension WitnessGenerator {
    /// Generates a nested `Synthesized` struct that conforms to the original protocol.
    ///
    /// This struct acts as a type-erased container, holding a `context` and a `witness`
    /// table. It forwards protocol requirements to the witness table.
    ///
    /// For a protocol like:
    /// ```swift
    /// protocol PricingService {
    ///     func price(_ item: String) -> Int
    /// }
    /// ```
    /// This function generates:
    /// ```swift
    /// struct Synthesized: PricingService {
    ///     let context: A
    ///     let witness: PricingServiceWitness<A>
    ///
    ///     func price(_ item: String) -> Int {
    ///         witness.price(context, item)
    ///     }
    /// }
    /// ```
    static func generateSynthesizedConformance(protocolDecl: ProtocolDeclSyntax) throws -> StructDeclSyntax {
        let protocolName = protocolDecl.name.text
        let witnessStructName = "\(protocolName)Witness"

        let requirements = Self.requirements(protocolDecl)
        let accessLevel = accessModifier(protocolDecl)
        let accessLevelPrefix = accessLevel != nil ? "public " : ""

        let memberBlock = try MemberBlockItemListSyntax {
            VariableDeclSyntax(
                modifiers: accessLevel != nil ? [DeclModifierSyntax(name: .keyword(.public))] : [],
                bindingSpecifier: .keyword(.let),
                bindings: [
                    PatternBindingSyntax(
                        pattern: IdentifierPatternSyntax(identifier: .identifier("context")),
                        typeAnnotation: TypeAnnotationSyntax(type: IdentifierTypeSyntax(name: .identifier(genericLabel)))
                    )
                ]
            )
            VariableDeclSyntax(
                modifiers: accessLevel != nil ? [DeclModifierSyntax(name: .keyword(.public))] : [],
                bindingSpecifier: .keyword(.var),
                bindings: [
                    PatternBindingSyntax(
                        pattern: IdentifierPatternSyntax(identifier: .identifier("strategy")),
                        typeAnnotation: TypeAnnotationSyntax(type: OptionalTypeSyntax(wrappedType: IdentifierTypeSyntax(name: .identifier("String"))))
                    )
                ]
            )

            MemberBlockItemSyntax(
                decl: try InitializerDeclSyntax("\(raw: accessLevelPrefix)init(context: A, strategy: String? = nil)") {
                    "self.context = context"
                    "self.strategy = strategy"
                }
            )

            for req in requirements {
                if req.kind == .function {
                    try generateMethod(
                        for: req,
                        protocolDecl: protocolDecl,
                        synthesizedStructName: "Synthesized",
                        witnessStructName: witnessStructName
                    )
                } else if req.kind == .variable {
                    try generateComputedProperty(
                        for: req,
                        protocolDecl: protocolDecl,
                        synthesizedStructName: "Synthesized",
                        witnessStructName: witnessStructName
                    )
                }
            }
        }

        return StructDeclSyntax(
            modifiers: accessLevel != nil ? [DeclModifierSyntax(name: .keyword(.public))] : [],
            name: .identifier("Synthesized"),
            inheritanceClause: InheritanceClauseSyntax {
                InheritedTypeSyntax(type: IdentifierTypeSyntax(name: protocolDecl.name))
            },
            memberBlock: MemberBlockSyntax(members: memberBlock)
        )
    }

    private static func generateMethod(
        for requirement: (name: TokenSyntax, static: Bool, kind: RequirementKind, parameters: [FunctionParameterSyntax]),
        protocolDecl: ProtocolDeclSyntax,
        synthesizedStructName: String,
        witnessStructName: String
    ) throws -> FunctionDeclSyntax {

        guard let funcDecl = protocolDecl.memberBlock.members
            .compactMap({ $0.decl.as(FunctionDeclSyntax.self) })
            .first(where: { $0.name.text == requirement.name.text }) else {
            throw MacroError(message: "Could not find function declaration for requirement '\(requirement.name.text)'")
        }

        let returnType = funcDecl.signature.returnClause?.type ?? TypeSyntax(stringLiteral: "Void")

        class SelfReplacer: SyntaxRewriter {
            let replacement: String
            init(replacement: String) {
                self.replacement = replacement
            }
            override func visit(_ node: IdentifierTypeSyntax) -> TypeSyntax {
                if node.name.text == "Self" {
                    return TypeSyntax(stringLiteral: replacement)
                }
                return super.visit(node)
            }
        }

        let newReturnType = SelfReplacer(replacement: synthesizedStructName).visit(returnType)
        let funcSignature = funcDecl.signature.with(\.returnClause, ReturnClauseSyntax(type: newReturnType))
        let accessLevel = accessModifier(protocolDecl)

        var modifiers: [DeclModifierSyntax] = []
        if let access = accessLevel {
            modifiers.append(access)
        }
        if requirement.static {
            modifiers.append(DeclModifierSyntax(name: .keyword(.static)))
        }

        var arguments: [String] = []
        if !requirement.static {
            arguments.append("context")
        }
        arguments.append(contentsOf: funcDecl.signature.parameterClause.parameters.map { param in
            param.secondName?.text ?? param.firstName.text
        })
        let argumentList = arguments.joined(separator: ", ")
        let tryKeyword = funcDecl.signature.effectSpecifiers?.throwsClause?.throwsSpecifier != nil ? "try " : ""
        let awaitKeyword = funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil ? "await " : ""
        
        return FunctionDeclSyntax(
            attributes: funcDecl.attributes,
            modifiers: DeclModifierListSyntax(modifiers),
            name: funcDecl.name,
            genericParameterClause: funcDecl.genericParameterClause,
            signature: funcSignature,
            genericWhereClause: funcDecl.genericWhereClause
        ) {

            let strategyParam = requirement.static ? "\"static\"" : "strategy"
            "@LookedUp(strategy: \(raw: strategyParam)) var witness: \(raw: witnessStructName)"
            let witnessCall: TokenSyntax = "return \(raw: tryKeyword)\(raw: awaitKeyword)witness.\(raw: requirement.name.text)(\(raw: argumentList))"
            if returnType.description.contains("Self") {
                "let newValue = \(raw: witnessCall)"
                "return .init(context: newValue, strategy: strategy)"
            } else {
                "\(raw: witnessCall)"
            }
        }
    }

    private static func generateComputedProperty(
        for requirement: (name: TokenSyntax, static: Bool, kind: RequirementKind, parameters: [FunctionParameterSyntax]),
        protocolDecl: ProtocolDeclSyntax,
        synthesizedStructName: String,
        witnessStructName: String
    ) throws -> VariableDeclSyntax {
        guard let varDecl = protocolDecl.memberBlock.members
            .compactMap({ $0.decl.as(VariableDeclSyntax.self) })
            .first(where: { $0.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == requirement.name.text }) else {
            throw MacroError(message: "Could not find var declaration for requirement '\(requirement.name.text)'")
        }

        var type = varDecl.bindings.first?.typeAnnotation?.type ?? TypeSyntax(stringLiteral: "Void")

        class SelfReplacer: SyntaxRewriter {
            let replacement: String
            init(replacement: String) {
                self.replacement = replacement
            }
            override func visit(_ node: IdentifierTypeSyntax) -> TypeSyntax {
                if node.name.text == "Self" {
                    return TypeSyntax(stringLiteral: replacement)
                }
                return super.visit(node)
            }
        }

        type = SelfReplacer(replacement: synthesizedStructName).visit(type)

        let propertyName = requirement.name.text
        let accessLevel = accessModifier(protocolDecl)

        let getterBody: String
        if requirement.static {
            getterBody = "witness.\(propertyName)()"
        } else {
            getterBody = "witness.\(propertyName)(context)"
        }
        let strategyParam = requirement.static ? "\"static\"" : "strategy"

        let getter = AccessorDeclSyntax(
            accessorSpecifier: .keyword(.get),
            body: CodeBlockSyntax(statements: CodeBlockItemListSyntax {
                "@LookedUp(strategy: \(raw: strategyParam) var witness: \(raw: witnessStructName)"
                CodeBlockItemSyntax(stringLiteral: getterBody)
            })
        )

        var modifiers: [DeclModifierSyntax] = []
        if let access = accessLevel {
            modifiers.append(access)
        }
        if requirement.static {
            modifiers.append(DeclModifierSyntax(name: .keyword(.static)))
        }

        return VariableDeclSyntax(
            modifiers: DeclModifierListSyntax(modifiers),
            bindingSpecifier: .keyword(.var),
            bindings: [
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier(propertyName)),
                    typeAnnotation: TypeAnnotationSyntax(type: type),
                    accessorBlock: .init(accessors: .accessors(AccessorDeclListSyntax([getter])))
                )
            ]
        )
    }
}

