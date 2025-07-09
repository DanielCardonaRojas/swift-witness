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
                bindingSpecifier: .keyword(.let),
                bindings: [
                    PatternBindingSyntax(
                        pattern: IdentifierPatternSyntax(identifier: .identifier("witness")),
                        typeAnnotation: TypeAnnotationSyntax(type: IdentifierTypeSyntax(name: .identifier(witnessStructName)))
                    )
                ]
            )

            for req in requirements {
                if req.kind == .function {
                    try generateMethod(
                        for: req,
                        protocolDecl: protocolDecl,
                        synthesizedStructName: "Synthesized"
                    )
                } else if req.kind == .variable {
                    try generateComputedProperty(
                        for: req,
                        protocolDecl: protocolDecl,
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

    /// Generates a method implementation for the `Synthesized` struct.
    ///
    /// The generated method forwards the call to the corresponding closure on the `witness`
    /// property, passing the `context` as the first argument.
    ///
    /// For a protocol method:
    /// ```swift
    /// func price(_ item: String) -> Int
    /// ```
    /// This generates the following implementation within the `Synthesized` struct:
    /// ```swift
    /// func price(_ item: String) -> Int {
    ///     witness.price(context, item)
    /// }
    /// ```
    private static func generateMethod(
        for requirement: (name: TokenSyntax, static: Bool, kind: RequirementKind, parameters: [FunctionParameterSyntax]),
        protocolDecl: ProtocolDeclSyntax,
        synthesizedStructName: String
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
            let arguments = ["context"] + funcDecl.signature.parameterClause.parameters.map { param in
                param.secondName?.text ?? param.firstName.text
            }
            let argumentList = arguments.joined(separator: ", ")
            let tryKeyword = funcDecl.signature.effectSpecifiers?.throwsSpecifier != nil ? "try " : ""
            let awaitKeyword = funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil ? "await " : ""

            "let newValue = \(raw: tryKeyword)\(raw: awaitKeyword)witness.\(raw: requirement.name.text)(\(raw: argumentList))"

            if returnType.description.contains("Self") {
                "return .init(context: newValue, witness: witness)"
            } else if returnType.description != "Void" {
                "return newValue"
            }
        }
    }

    /// Generates a computed property implementation for the `Synthesized` struct.
    ///
    /// The generated property\'s getter forwards the call to the corresponding closure on the
    /// `witness` property, passing the `context` as an argument.
    ///
    /// For a protocol property:
    /// ```swift
    /// var price: Int { get }
    /// ```
    /// This generates the following implementation within the `Synthesized` struct:
    /// ```swift
    /// var price: Int {
    ///     witness.price(context)
    /// }
    /// ```
    private static func generateComputedProperty(
        for requirement: (name: TokenSyntax, static: Bool, kind: RequirementKind, parameters: [FunctionParameterSyntax]),
        protocolDecl: ProtocolDeclSyntax,
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
            if type.description.contains(synthesizedStructName) {
                 "let _ = witness.\(raw: propertyName)(context)"
                 "return .init(context: context, witness: witness)"
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
