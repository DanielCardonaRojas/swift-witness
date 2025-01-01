public enum WitnessOptions: String {
  case utilities // map, pullback or iso
  case conformanceInit // a initializer creating a Witness from a conformance to the protocol
}

@attached(peer, names: suffixed(Witness))
public macro Witnessed(_ options: [WitnessOptions] = []) = #externalMacro(module: "WitnessMacros", type: "WitnessMacro")
