
import SwiftSyntax
import SwiftSyntaxBuilder
import WitnessTypes

extension WitnessGenerator {
    static func generateSynthesizedByTableConformance(protocolDecl: ProtocolDeclSyntax) throws -> StructDeclSyntax {
        let protocolName = protocolDecl.name.text
        let witnessStructName = "\(protocolName)Witness"

        let requirements = Self.requirements(protocolDecl)
        let accessLevel = accessModifier(protocolDecl)
        let accessLevelPrefix = accessLevel != nil ? "public " : ""

        let memberBlock = try MemberBlockItemListSyntax {
            VariableDeclSyntax(
                modifiers: accessLevel != nil ? [DeclModifierSyntax(name: .keyword(.public))] : [],
                bindingSpecifier: .keyword(.var),
                bindings: [
                    PatternBindingSyntax(
                        pattern: IdentifierPatternSyntax(identifier: .identifier("strategy")),
                        typeAnnotation: TypeAnnotationSyntax(type: IdentifierTypeSyntax(name: .identifier("String")))
                    )
                ]
            )
            VariableDeclSyntax(
                modifiers: accessLevel != nil ? [DeclModifierSyntax(name: .keyword(.public))] : [],
                bindingSpecifier: .keyword(.let),
                bindings: [
                    PatternBindingSyntax(
                        pattern: IdentifierPatternSyntax(identifier: .identifier("context")),
                        typeAnnotation: TypeAnnotationSyntax(type: IdentifierTypeSyntax(name: .identifier("Any")))
                    )
                ]
            )
            VariableDeclSyntax(
                modifiers: accessLevel != nil ? [DeclModifierSyntax(name: .keyword(.public))] : [],
                bindingSpecifier: .keyword(.var),
                bindings: [
                    PatternBindingSyntax(
                        pattern: IdentifierPatternSyntax(identifier: .identifier("contextType")),
                        typeAnnotation: TypeAnnotationSyntax(type: IdentifierTypeSyntax(name: .identifier("String")))
                    )
                ]
            )

            MemberBlockItemSyntax(
                decl: try InitializerDeclSyntax("\(raw: accessLevelPrefix)init<Context>(context: Context, strategy: String? = nil)") {
                    "self.context = context"
                    #"self.contextType = "\(String(describing: Context.self))""#
                    #"self.strategy = strategy ?? "default""#
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
                        witnessStructName: witnessStructName,
                        synthesizedStructName: "Synthesized"
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

        return FunctionDeclSyntax(
            attributes: funcDecl.attributes,
            modifiers: accessLevel != nil ? [DeclModifierSyntax(name: .keyword(.public))] : [],
            name: funcDecl.name,
            genericParameterClause: funcDecl.genericParameterClause,
            signature: funcSignature,
            genericWhereClause: funcDecl.genericWhereClause
        ) {
            "let table = \(raw: witnessStructName)<Any>.Table()"
            #"guard let witness = table.witness(for: contextType, label: strategy) else {"#
            #"    fatalError("Table for \(Self.self) does not contain a registered witness for strategy: \(strategy)")"#
            "}"

            let arguments = ["context"] + funcDecl.signature.parameterClause.parameters.map { param in
                param.secondName?.text ?? param.firstName.text
            }
            let argumentList = arguments.joined(separator: ", ")

            "let newValue = witness.\(raw: requirement.name.text)(\(raw: argumentList))"

            if returnType.description.contains("Self") {
                "return .init(context: newValue, strategy: strategy)"
            } else if returnType.description != "Void" {
                "return newValue"
            }
        }
    }

    private static func generateComputedProperty(
        for requirement: (name: TokenSyntax, static: Bool, kind: RequirementKind, parameters: [FunctionParameterSyntax]),
        protocolDecl: ProtocolDeclSyntax,
        witnessStructName: String,
        synthesizedStructName: String
    ) throws -> VariableDeclSyntax {
        guard let varDecl = protocolDecl.memberBlock.members
            .compactMap({ $0.decl.as(VariableDeclSyntax.self) })
            .first(where: { $0.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == requirement.name.text }) else {
            throw MacroError(message: "Could not find var declaration for requirement '\(requirement.name.text)'")
        }

        guard let binding = varDecl.bindings.first,
              var type = binding.typeAnnotation?.type else {
            throw MacroError(message: "Variable requirement '\(requirement.name.text)' must have a type annotation.")
        }

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

        let getter = try AccessorDeclSyntax("get") {
            "let table = \(raw: witnessStructName)<Any>.Table()"
            #"guard let witness = table.witness(for: contextType, label: strategy) else {"#
            #"    fatalError("Table for \(Self.self) does not contain a registered witness for strategy: \(strategy)")"#
            "}"
            if type.description.contains(synthesizedStructName) {
                 "let _ = witness.\(raw: propertyName)(context)"
                 "return .init(context: context, strategy: strategy)"
            } else {
                "return witness.\(raw: propertyName)(context)"
            }
        }

        return VariableDeclSyntax(
            modifiers: accessLevel != nil ? [.init(name: .keyword(.public))] : [],
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
