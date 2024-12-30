public enum WitnessOptions: String {
  case utilities // map, pullback or iso
}

@attached(peer, names: suffixed(Witness))
public macro Witnessed(_ options: [WitnessOptions] = []) = #externalMacro(module: "WitnessMacros", type: "WitnessMacro")
