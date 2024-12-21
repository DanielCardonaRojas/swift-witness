public enum WitnessOptions: String {
  case conformance //add code to conform to the protocol and provide interoperability
}

@attached(peer, names: suffixed(Witness))
public macro Witness(_ options: [WitnessOptions] = []) = #externalMacro(module: "WitnessMacros", type: "WitnessMacro")
