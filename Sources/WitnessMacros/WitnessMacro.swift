import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import WitnessGenerator

@main
struct WitnessPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        WitnessMacro.self,
    ]
}

public enum WitnessMacro: PeerMacro {

  public static func expansion(
    of node: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard let protocolDecl = declaration.as(ProtocolDeclSyntax.self) else {
      throw MacroError(message: "@WitnessMacro only works on protocols declarations")
    }
    return try WitnessGenerator.processProtocol(protocolDecl: protocolDecl)
  }
}
