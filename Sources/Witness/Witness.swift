import WitnessTypes

@attached(peer, names: suffixed(Witness))
public macro Witnessed(_ options: [WitnessOptions] = []) = #externalMacro(module: "WitnessMacros", type: "WitnessMacro")
