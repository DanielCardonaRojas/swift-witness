@attached(peer, names: suffixed(Witness))
public macro Witness() = #externalMacro(module: "WitnessMacros", type: "WitnessMacro")
