import Witness
import Foundation

@Witnessed([.utilities])
protocol Comparable {
  func compare(_ other: Self) -> Bool
}

@Witnessed([.utilities])
protocol Combinable {
  func combine(_ other: Self) -> Self
}

typealias Combining<A> = CombinableWitness<A>

@Witnessed
protocol Diffable {
  static func diff(old: Self, new: Self) -> (String, [String])?
  var data: Data { get }
  static func from(data: Data) -> Self
}

typealias Diffing<A> = DiffableWitness<A>

@Witnessed([.utilities])
protocol Snapshottable {
  associatedtype Format: Diffable
  static var pathExtension: String { get }
  var snapshot: Format { get }
}

typealias Snapshotting<Value, Format: Diffable> = SnapshottableWitness<Value, Format>

@Witnessed
protocol Convertible {
  associatedtype To
  func convert() -> To
}

typealias Converting<A, To> = ConvertibleWitness<A, To>

func examples() {
  _ = [1, 2, 3, 4].reduce(0, .sum)
  _ = [Double(1), 2, 3, 4].reduce(0, .sum)
  _ = [CGFloat(1), 2, 3, 4].reduce(0, .prod)
  _ = ["Hello", " ", "World"].reduce("", .concat)
  _ = [[1],[2, 3],[4]].reduce([], .concat)
}

