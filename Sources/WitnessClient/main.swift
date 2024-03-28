import Witness

@Witness
protocol Combinable {
  func combine(_ other: Self) -> Self
}


struct Combining<A> {
  let combine: (A, A) -> A
}
