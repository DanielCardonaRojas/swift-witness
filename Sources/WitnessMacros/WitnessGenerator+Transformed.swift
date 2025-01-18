//
//  WitnessGenerator+Transformed.swift
//  Witness
//
//  Created by Daniel Cardona on 8/01/25.
//
import SwiftSyntax
import SwiftSyntaxBuilder

/// Generates utility method for transforming  a `Witness<A>` into a `Witness<B>`
extension WitnessGenerator {
  static func witnessTransformation(
    _ protocolDecl: ProtocolDeclSyntax
  ) -> MemberBlockItemSyntax? {

    let variances = witnessStructVariance(protocolDecl)
    // The name of the witness struct we generated, e.g., `CombinableWitness`.
    let witnessName = witnessStructName(protocolDecl) // e.g. "CombinableWitness"

    let semantics = transformSemantics(from: variances)

    var member: MemberBlockItemSyntax?
    if let semantics {
      member = MemberBlockItemSyntax(
        decl: transformedWitness(
          semantic: semantics,
          protocolDecl: protocolDecl,
          witnessName: witnessName
        )
      )
    }
    return member
  }

  /// Generates method transforming witness to another type
  /// ```swift
  /// extension <WitnessName> {
  ///   func transform<B>(_ f: @escaping (B) -> A) -> <WitnessName><B> {
  ///     .init(combine: { b1, b2 in
  ///       self.combine(f(b1), f(b2))
  ///     })
  ///   }
  /// }
  /// ```
  /// or:
  /// ```swift
  /// extension <WitnessName> {
  ///   func transform<B>(_ f: @escaping (A) -> B) -> <WitnessName><B> {
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
  ///   func transform<B>(
  ///     pullback: @escaping (B) -> A,
  ///     map: @escaping (A) -> B
  ///   ) -> <WitnessName><B> {
  ///     .init(combine: { b1, b2 in
  ///       let r = self.combine(pullback(b1), pullback(b2))
  ///       return map(r)
  ///     })
  ///   }
  /// }
  /// ```
  static func transformedWitness(
    semantic: TransformedWitnessSemantic,
    protocolDecl: ProtocolDeclSyntax,
    witnessName: TokenSyntax
  ) -> FunctionDeclSyntax {
    // `func transform<B>(_ pullback: @escaping (B) -> A, map: @escaping (A) -> B) -> <WitnessName><B>`
    FunctionDeclSyntax(
      modifiers: .init(itemsBuilder: {
        if let accessModifier = accessModifier(protocolDecl) {
          accessModifier
        }
      }),
      name: .identifier("transform"),
      genericParameterClause: GenericParameterClauseSyntax(
        parameters: GenericParameterListSyntax {
          GenericParameterSyntax(name: .identifier("B"))
        }
      ),
      signature: FunctionSignatureSyntax(
        parameterClause: FunctionParameterClauseSyntax {
          // ( _ pullback: @escaping (B) -> A )
          if semantic == .iso || semantic == .pullback {
            closureParameterTransformType(from: "B", to: genericLabel, name: "pullback")
          }
          // ( map: @escaping (A) -> B )
          if semantic == .iso || semantic == .map {
            closureParameterTransformType(from: genericLabel, to: "B", name: "map")
          }
        },
        returnClause: ReturnClauseSyntax(
          type: TypeSyntax(
            genericType(
              witnessName: witnessName,
              genericArgumentClause: transformGenericArgumentClause(protocolDecl)
            )
          )
        )
      )
    ) {
      CodeBlockItemListSyntax {
        transformedInstance(protocolDecl)
      }
    }
  }

  /// Creates a closure type function parameter like: `map: @espacing (A) -> B` where `A` is `genericIn` and `B` is `genericOut`
  static func closureParameterTransformType(from genericIn: String, to genericOut: String, name: String) -> FunctionParameterSyntax {
    FunctionParameterSyntax(
      firstName: .identifier(name),
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
                type: IdentifierTypeSyntax(name: .identifier(genericIn))
              )
            },
            returnClause: ReturnClauseSyntax(
              type: IdentifierTypeSyntax(name: .identifier(genericOut))
            )
          )
      )
    )
  }

  static func transformGenericArgumentClause(
    _ protocolDecl: ProtocolDeclSyntax,
    typeReplacementForSelf: String = "B"
  ) -> GenericArgumentClauseSyntax {
      let nonPrimary = associatedTypeToGenericParam(protocolDecl, primary: false)
      let primary = associatedTypeToGenericParam(protocolDecl, primary: true)

    let parameters = GenericArgumentListSyntax(itemsBuilder: {
      GenericArgumentSyntax(
        argument: IdentifierTypeSyntax(
          name: TokenSyntax(stringLiteral: typeReplacementForSelf)
        )
      )

        for parameter in primary {
          parameter.toGenericArgumentSyntax()
        }

        for parameter in nonPrimary {
          parameter.toGenericArgumentSyntax()
        }
      })

    return GenericArgumentClauseSyntax(arguments: parameters)
  }

  /// Creates the new instance with transformed witness 
  /// ```swift
  /// .init(combine: { b1, b2 in
  ///   map(self.combine(pullback(b1), pullback(b2)))
  /// })
  /// ```
  static func transformedInstance(_ protocolDecl: ProtocolDeclSyntax) -> FunctionCallExprSyntax {
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
      rightParen: .rightParenToken().with(\.leadingTrivia, .newline)
    )

  }

  /// Argument to initializer
  ///
  /// ```swift
  /// .init(
  ///    combine: { // Closure expression }  // <- Generate this
  ///  )
  /// ```
  static func constructorArguments(_ protocolDecl: ProtocolDeclSyntax) -> [LabeledExprSyntax] {
    protocolDecl.memberBlock.members
      .flatMap(
{ (member: MemberBlockItemSyntax) -> [LabeledExprSyntax] in
        if let functionDecl = member.decl.as(FunctionDeclSyntax.self) {
          return [LabeledExprSyntax(
            label: functionDecl.name,
            colon: .colonToken(),
            expression: transformedClosure(functionDecl, protocolDecl: protocolDecl)
          ).with(\.leadingTrivia, .newline)]
        }
        else if let variableDecl = member.decl.as(VariableDeclSyntax.self),
           let identifier = variableDecl.bindings.first?.pattern.as(IdentifierPatternSyntax.self) {
          return [LabeledExprSyntax(
            label: identifier.identifier,
            colon: .colonToken(),
            expression: transformedVariableClosure(variableDecl, protocolDecl: protocolDecl)
          ).with(\.leadingTrivia, .newline)]
        }
        else if let associatedTypeDecl = member.decl.as(AssociatedTypeDeclSyntax.self) {
          // For example diffable = self.diffable where diffable: DiffableWitness<Format>
          let inheritedTypes = (
            associatedTypeDecl.inheritanceClause?.inheritedTypes ?? []
          )


          let witnessDependenciesAssignments: [LabeledExprSyntax?] = inheritedTypes.map { inheritedType in
            guard let identifierType = inheritedType.type.as(IdentifierTypeSyntax.self) else {
              return nil
            }

            let witnessVariableName = identifierType.name.text.lowercaseFirst()

            return LabeledExprSyntax(
              label: .identifier(witnessVariableName),
              colon: .colonToken(),
              expression: MemberAccessExprSyntax(
                base: DeclReferenceExprSyntax(baseName: .identifier("self")),
                declName: DeclReferenceExprSyntax(baseName: .identifier(witnessVariableName))
              )
            ).with(\.leadingTrivia, .newline)

          }

          return witnessDependenciesAssignments.compactMap({ $0 })

        }

        return []
      })
  }


  static func transformedVariableClosure(_ variableDecl: VariableDeclSyntax, protocolDecl: ProtocolDeclSyntax) -> ClosureExprSyntax {
    let generics = associatedTypeToGenericParam(protocolDecl, primary: nil)
    let closureType = variableRequirementWitnessType(variableDecl)
    let variableName = variableDecl.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier ?? .init(stringLiteral: "Unknown")
    let variableType = variableDecl.bindings.first?.typeAnnotation
    let closureCall = FunctionCallExprSyntax(
      calledExpression: MemberAccessExprSyntax(
        base: DeclReferenceExprSyntax(baseName: .identifier("self")),
        declName: DeclReferenceExprSyntax(baseName: variableName)
      ),
      leftParen: .leftParenToken(),
      rightParen: .rightParenToken(),
      argumentsBuilder: {
        // Rest of params
        for (index, parameter) in closureType.parameters.enumerated() {
          if varianceOf(parameter: parameter, generics: generics) == .contravariant {
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

    // TODO: Also check for associated types
    let hasSelfInType = variableType?.contains(targetTypeName: "Self") ?? false

    let variance: Variance = hasSelfInType ? .covariant : .invariant

    // If contains Self in the return type then map the return value
    if variance == .covariant {
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

  /// Creates an a closure expression with converted input and outputs.
  ///
  /// This is used in the transform the closures of a Witness<A> to a Witness<B>
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
          if varianceOf(parameter: parameter, generics: generics) == .contravariant {
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
      functionDecl: functionDecl,
      generics: generics
    )

    // If contains Self in the return type then map the return value
    if variance.contains(.covariant) {
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

  static func transformSemantics(from variances: Set<Variance>) -> TransformedWitnessSemantic? {
    if variances.isSuperset(of: [.contravariant, .covariant]) {
      return .iso
    }

    if variances.contains(.contravariant) {
      return .pullback
    }

    if variances.contains(.covariant) {
      return .map
    }

    return nil

  }

  static func variance(
    variableDecl: VariableDeclSyntax,
      generics: [GenericParameterSyntax]
  ) -> Set<Variance> {
    var declaredGenericNames = Set(generics.map { $0.name.text })
    declaredGenericNames.insert("Self")
    var genericsInParams = Set<String>()

    if !variableDecl.isModifiedWith(.static) {
      genericsInParams.insert("Self")
    }


    var genericsInReturn = Set<String>()
    if let variableType = variableDecl.bindings.first?.typeAnnotation?.type {
        let collector = GenericNameCollector(declaredGenerics: declaredGenericNames)
        collector.walk(variableType)
        genericsInReturn.formUnion(collector.foundGenerics)
    }

    var variances = Set<Variance>()

    if !genericsInReturn.isEmpty {
      variances.insert(.covariant)
    }

    if !genericsInParams.isEmpty {
      variances.insert(.contravariant)
    }

    if genericsInParams.isEmpty && genericsInReturn.isEmpty {
      variances.insert(.invariant)
    }

    return variances
  }
  /// **Core method**: Determines the variance of a function signature by checking
  /// how the generic parameters are used in the function's parameter list (input)
  /// and return type (output).
  ///
  /// - Parameters:
  ///   - functionSignature: The syntax node describing the function signature.
  ///   - generics: The generic parameters (e.g., `T`, `U`) declared on the function.
  /// - Returns: A `Variance` value (`.contravariant`, `.covariant`, or `.invariant`).
  static func variance(
      functionDecl: FunctionDeclSyntax,
      generics: [GenericParameterSyntax]
  ) -> Set<Variance> {
      let functionSignature = functionDecl.signature
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

      if !functionDecl.isModifiedWith(.static) {
        genericsInParams.insert("Self")
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
      let parameterAndReturnIntersection = genericsInParams.intersection(genericsInReturn)
      var variances = Set<Variance>()

      if !genericsInReturn.isEmpty {
        variances.insert(.covariant)
      }

      if !genericsInParams.isEmpty {
        variances.insert(.contravariant)
      }

      if genericsInParams.isEmpty && genericsInReturn.isEmpty {
        variances.insert(.invariant)
      }

      return variances
  }

  static func varianceOf(
    parameter: TupleTypeElementSyntax,
    generics: [GenericParameterSyntax]
  ) -> Variance {
    var declaredGenericNames = Set(generics.map { $0.name.text })
    declaredGenericNames.insert(Self.genericLabel)
    let collector = GenericNameCollector(declaredGenerics: declaredGenericNames)
    collector.walk(parameter)
    let genericsInParamType = collector.foundGenerics

    if !genericsInParamType.intersection(declaredGenericNames).isEmpty {
      return .contravariant
    }

    return .invariant
  }

  /// Determines if the generated witness struct need a pullback, map or iso method.
  /// if the set contains a covariant and contravariant then an iso is required
  /// if the set contains covariant and not contravariant then a map is required
  /// if the set contains a contravariant and not a covariant then a pullback is required
  static func witnessStructVariance(_ protocolDecl: ProtocolDeclSyntax) -> Set<Variance> {
    let generics = associatedTypeToGenericParam(protocolDecl, primary: nil)
    let variances: [Variance] = protocolDecl.memberBlock.members.flatMap { member in
      if let functionDecl = member.decl.as(FunctionDeclSyntax.self) {
        return variance(functionDecl: functionDecl, generics: generics)
      }
      if let variableDecl = member.decl.as(VariableDeclSyntax.self) {
        return variance(variableDecl: variableDecl, generics: generics)
      }

      return Set<Variance>()
    }

    return Set(variances)
  }
}
