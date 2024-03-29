import Witness
import Foundation

@Witness
protocol Combinable {
  func combine(_ other: Self) -> Self
}

typealias Combining<A> = CombinableWitness<A>

@Witness
protocol Diffable {
  static func diff(old: Self, new: Self) -> (String, [String])?
  var data: Data { get }
  static func from(data: Data) -> Self
}

@Witness
protocol Snapshottable {
  associatedtype Format: Diffable
  static var pathExtension: String { get }
  var snapshot: Format { get }
}

func examples() {
  _ = [1, 2, 3, 4].reduce(0, .sum)
  _ = [Double(1), 2, 3, 4].reduce(0, .sum)
  _ = [CGFloat(1), 2, 3, 4].reduce(0, .prod)
  _ = ["Hello", " ", "World"].reduce("", .concat)
  _ = [[1],[2, 3],[4]].reduce([], .concat)
}

