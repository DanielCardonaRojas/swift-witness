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
    let variance = witnessStructVariance(protocolDecl)
    let convertedProtocolRequirements: [MemberBlockItemSyntax] = protocolDecl.memberBlock.members.compactMap { member in
      if let member = processProtocolRequirement(member.decl) {
        return member
      }
      return nil
    }

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

          for member in convertedProtocolRequirements {
            member
          }
        })
      )
    )

    return [
      DeclSyntax(structDecl)
    ]
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

  static func witnessStructName(_ protocolDecl: ProtocolDeclSyntax) -> TokenSyntax {
    "\(raw: protocolDecl.name.text)Witness"
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
