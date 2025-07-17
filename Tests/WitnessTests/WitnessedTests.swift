//
//  WitnessedTests.swift
//  Witness
//
//  Created by Daniel Cardona on 15/01/25.
//

import XCTest
import MacroTesting
import WitnessMacros

final class WitnessedTests: XCTestCase {
  override func invokeTest() {
    withMacroTesting(
      record: false,
      macros: ["Witnessed": WitnessMacro.self]
    ) {
      super.invokeTest()
    }
  }

    func testSynthesizedConformance() {
        assertMacro {
            """
            @Witnessed(.synthesizedConformance)
            protocol PricingService {
                func price(_ item: String) async throws -> Int
            }
            """
        } expansion: {
          """
          protocol PricingService {
              func price(_ item: String) async throws -> Int
          }

          struct PricingServiceWitness<A> {
              let price: (A, String) async throws -> Int
              struct Synthesized: PricingService {
                  let context: A
                  var strategy: String?
                  func price(_ item: String) async throws -> Int {
                      @LookedUp(strategy: strategy) var witness: PricingServiceWitness
                      return try await witness.price(context, item)
                  }
              }
          }
          """
        }
    }

    func testErased() {
        assertMacro {
            """
            @Witnessed([.synthesizedByTableConformance, .utilities])
            protocol Fake {
                func fake() -> Self
            }
            """
        } expansion: {
          #"""
          protocol Fake {
              func fake() -> Self
          }

          struct FakeWitness<A>: ErasableWitness {
              let fake: (A) -> A
              func transform<B>(
                  pullback: @escaping (B) -> A,
                  map: @escaping (A) -> B
              ) -> FakeWitness<B> {
                  .init(
                      fake: {
                          map(self.fake(pullback($0)))
                      }
                  )
              }
              func erased() -> FakeWitness<Any> {
                  transform(pullback: { instance in
                          instance as! A
                      }, map: { instance in
                          instance
                      })
              }
              struct Synthesized: Fake {
                  var strategy: String
                  let context: Any
                  var contextType: String
                  init<Context>(context: Context, strategy: String? = nil) {
                      self.context = context
                      self.contextType = "\(String(describing: Context.self))"
                      self.strategy = strategy ?? "default"
                  }
                  func fake() -> Synthesized {
                      let table = FakeWitness<Any>.Table()
                      guard let witness = table.witness(for: contextType, label: strategy) else {
                          fatalError("Table for \(Self.self) does not contain a registered witness for strategy: \(strategy)")}
                      let newValue = witness.fake(context)
                      return .init(context: newValue, strategy: strategy)
                  }
              }
          }
          """#
        }
    }
    
    func testErasedPullback() {
        assertMacro {
            """
            @Witnessed([.utilities, .synthesizedByTableConformance])
            protocol PricingService {
                func price(_ item: String) -> Double
            }
          """
        } expansion: {
          #"""
            protocol PricingService {
                func price(_ item: String) -> Double
            }

            struct PricingServiceWitness<A>: ErasableWitness {
              let price: (A, String) -> Double
              func transform<B>(
                pullback: @escaping (B) -> A
              ) -> PricingServiceWitness<B> {
                .init(
                  price: {
                    self.price(pullback($0), $1)
                  }
                )
              }
              func erased() -> PricingServiceWitness<Any> {
                transform(pullback: { instance in
                    instance as! A
                  })
              }
              struct Synthesized: PricingService {
                var strategy: String
                let context: Any
                var contextType: String
                init<Context>(context: Context, strategy: String? = nil) {
                  self.context = context
                  self.contextType = "\(String(describing: Context.self))"
                  self.strategy = strategy ?? "default"
                }
                func price(_ item: String) -> Double {
                  let table = PricingServiceWitness<Any>.Table()
                  guard let witness = table.witness(for: contextType, label: strategy) else {
                      fatalError("Table for \(Self.self) does not contain a registered witness for strategy: \(strategy)")}
                  let newValue = witness.price(context, item)
                  return newValue
                }
              }
            }
          """#
        }
    }

  func testComparable() {
    assertMacro {
      """
      @Witnessed([.utilities])
      public protocol Comparable {
        func compare(_ other: Self) -> Bool
      }
      """
    } expansion: {
      """
      public protocol Comparable {
        func compare(_ other: Self) -> Bool
      }

      public struct ComparableWitness<A> {
        public let compare: (A, A) -> Bool

        public init(
          compare: @escaping (A, A) -> Bool
        ) {
          self.compare = compare
        }

        public func transform<B>(
          pullback: @escaping (B) -> A
        ) -> ComparableWitness<B> {
          .init(
            compare: {
              self.compare(pullback($0), pullback($1))
            }
          )
        }
      }
      """
    }
  }

  func testRandomNumberGenerator() {
    assertMacro {
      """
      @Witnessed([.utilities])
      public protocol RandomNumberGenerator {
        func random() -> Double
      }
      """
    } expansion: {
      """
      public protocol RandomNumberGenerator {
        func random() -> Double
      }

      public struct RandomNumberGeneratorWitness<A> {
        public let random: (A) -> Double

        public init(
          random: @escaping (A) -> Double
        ) {
          self.random = random
        }

        public func transform<B>(
          pullback: @escaping (B) -> A
        ) -> RandomNumberGeneratorWitness<B> {
          .init(
            random: {
              self.random(pullback($0))
            }
          )
        }
      }
      """
    }
  }

  func testFullyNamed() {
    assertMacro {
      """
      @Witnessed([.utilities])
      public protocol Comparable {
        func compare(_ other: Self) -> Bool
      }
      """
    } expansion: {
      """
      public protocol Comparable {
        func compare(_ other: Self) -> Bool
      }

      public struct ComparableWitness<A> {
        public let compare: (A, A) -> Bool

        public init(
          compare: @escaping (A, A) -> Bool
        ) {
          self.compare = compare
        }

        public func transform<B>(
          pullback: @escaping (B) -> A
        ) -> ComparableWitness<B> {
          .init(
            compare: {
              self.compare(pullback($0), pullback($1))
            }
          )
        }
      }
      """
    }
  }

  func testDiffable() {
    assertMacro {
      """
      @Witnessed()
      public protocol Diffable {
        static func diff(old: Self, new: Self) -> (String, [String])?
        var data: Data { get }
        static func from(data: Data) -> Self
      }
      """
    } expansion: {
      """
      public protocol Diffable {
        static func diff(old: Self, new: Self) -> (String, [String])?
        var data: Data { get }
        static func from(data: Data) -> Self
      }

      public struct DiffableWitness<A> {
        public let diff: (A, A) -> (String, [String])?
        public let data: (A) -> Data
        public let from: (Data) -> A

        public init(
          diff: @escaping (A, A) -> (String, [String])?,
          data: @escaping (A) -> Data ,
          from: @escaping (Data) -> A
        ) {
          self.diff = diff
          self.data = data
          self.from = from
        }
      }
      """
    }
  }

  func testSnapshottable() {
    assertMacro {
      """
      @Witnessed([.conformanceInit, .utilities])
      public protocol Snapshottable {
        associatedtype Format: Diffable
        static var pathExtension: String { get }
        var snapshot: Format { get }
      }
      """
    } expansion: {
      """
      public protocol Snapshottable {
        associatedtype Format: Diffable
        static var pathExtension: String { get }
        var snapshot: Format { get }
      }

      public struct SnapshottableWitness<A, Format> {
        public let diffable: DiffableWitness<Format>
        public let pathExtension: () -> String
        public let snapshot: (A) -> Format

        public init(
          diffable: DiffableWitness<Format>,
          pathExtension: @escaping () -> String ,
          snapshot: @escaping (A) -> Format
        ) {
          self.diffable = diffable
          self.pathExtension = pathExtension
          self.snapshot = snapshot
        }

        public init() where A: Snapshottable , Format: Diffable, A.Format == Format {
          self.diffable = .init()
          self.pathExtension = {
            A.pathExtension
          }
          self.snapshot = { instance in
            instance.snapshot
          }
        }

        public func transform<B>(
          pullback: @escaping (B) -> A
        ) -> SnapshottableWitness<B, Format> {
          .init(
            diffable: self.diffable,
            pathExtension: {
              self.pathExtension()
            },
            snapshot: {
              self.snapshot(pullback($0))
            }
          )
        }
      }
      """
    }

  }

  func testTogglable() {
    assertMacro {
      """
      @Witnessed()
      protocol Togglable {
        mutating func toggle()
      }
      """
    } expansion: {
      """
      protocol Togglable {
        mutating func toggle()
      }

      struct TogglableWitness<A> {
        let toggle: (inout A) -> Void
      }
      """
    }
  }

  func testDiffableWithUtilities() {
    assertMacro {
      """
      @Witnessed([.utilities])
      public protocol Diffable {
        static func diff(old: Self, new: Self) -> (String, [String])?
        var data: Data { get }
        static func from(data: Data) -> Self
      }
      """
    } expansion: {
      """
      public protocol Diffable {
        static func diff(old: Self, new: Self) -> (String, [String])?
        var data: Data { get }
        static func from(data: Data) -> Self
      }

      public struct DiffableWitness<A> {
        public let diff: (A, A) -> (String, [String])?
        public let data: (A) -> Data
        public let from: (Data) -> A

        public init(
          diff: @escaping (A, A) -> (String, [String])?,
          data: @escaping (A) -> Data ,
          from: @escaping (Data) -> A
        ) {
          self.diff = diff
          self.data = data
          self.from = from
        }

        public func transform<B>(
          pullback: @escaping (B) -> A,
          map: @escaping (A) -> B
        ) -> DiffableWitness<B> {
          .init(
            diff: {
              self.diff(pullback($0), pullback($1))
            },
            data: {
              self.data(pullback($0))
            },
            from: {
              map(self.from($0))
            }
          )
        }
      }
      """
    }
  }

  func testCombinable() {
    assertMacro {
      """
      @Witnessed([.utilities, .conformanceInit])
      protocol Combinable {
        func combine(_ other: Self) -> Self
      }
      """
    } expansion: {
      """
      protocol Combinable {
        func combine(_ other: Self) -> Self
      }

      struct CombinableWitness<A> {
        let combine: (A, A) -> A
        func transform<B>(
          pullback: @escaping (B) -> A,
          map: @escaping (A) -> B
        ) -> CombinableWitness<B> {
          .init(
            combine: {
              map(self.combine(pullback($0), pullback($1)))
            }
          )
        }
      }
      """
    }
  }

  func testConvertible() {
    assertMacro {
      """
      @Witnessed([.utilities, .conformanceInit])
      protocol Convertible {
        associatedtype To
        func convert() -> To
      }
      """
    } expansion: {
      """
      protocol Convertible {
        associatedtype To
        func convert() -> To
      }

      struct ConvertibleWitness<A, To> {
        let convert: (A) -> To
        func transform<B>(
          pullback: @escaping (B) -> A
        ) -> ConvertibleWitness<B, To> {
          .init(
            convert: {
              self.convert(pullback($0))
            }
          )
        }
      }
      """
    }
  }

  func testSubscript() {
    assertMacro {
    """
    @Witnessed()
    protocol BoolIndexed {
      subscript (_ value: Bool) -> Bool { get }
    }
    """
    } expansion: {
      """
      protocol BoolIndexed {
        subscript (_ value: Bool) -> Bool { get }
      }

      struct BoolIndexedWitness<A> {
        let indexedBy: (A, Bool) -> Bool
      }
      """
    }
  }

    func testService() {
        assertMacro {
            """
            @Witnessed([.synthesizedConformance])
            protocol DataService {
                func fetch() async throws -> Data
                func fetchFromCache() throws -> Data
            }
            """
        } expansion: {
          """
          protocol DataService {
              func fetch() async throws -> Data
              func fetchFromCache() throws -> Data
          }

          struct DataServiceWitness<A> {
              let fetch: (A) async throws -> Data
              let fetchFromCache: (A) throws -> Data
              struct Synthesized: DataService {
                  let context: A
                  var strategy: String?
                  func fetch() async throws -> Data {
                      @LookedUp(strategy: strategy) var witness: DataServiceWitness
                      return try await witness.fetch(context)
                  }
                  func fetchFromCache() throws -> Data {
                      @LookedUp(strategy: strategy) var witness: DataServiceWitness
                      return try witness.fetchFromCache(context)
                  }
              }
          }
          """
        }
    }

    func testSynthesizedWithVariable() {
        assertMacro {
            """
            @Witnessed([.synthesizedConformance])
            protocol PropertyService {
                var value: Int { get }
            }
            """
        } expansion: {
          """
          protocol PropertyService {
              var value: Int { get }
          }

          struct PropertyServiceWitness<A> {
              let value: (A) -> Int
              struct Synthesized: PropertyService {
                  let context: A
                  var strategy: String?
                  var value: Int {
                      get {
                          @LookedUp(strategy: strategy var witness: PropertyServiceWitness
                          witness.value(context)
                      }
                  }
              }
          }
          """
        }
    }

    func testRequirementWithConstrainedGeneric() {
        assertMacro {
            """
            @Witnessed
            protocol AnalyticsProtocol: Sendable {
                func logEvent<E: Identifiable>(_ event: E)
            }
            """
        } expansion: {
          """
          protocol AnalyticsProtocol: Sendable {
              func logEvent<E: Identifiable>(_ event: E)
          }

          struct AnalyticsProtocolWitness<A> {
              let logEvent: (A, any Identifiable) -> Void
          }
          """
        }
    }
    func testRequirementWithComposedGenericConstraint() {
        assertMacro {
            """
            @Witnessed
            protocol AnalyticsProtocol: Sendable {
                func logEvent<E: Identifiable & Codable>(_ event: E)
            }
            """
        } expansion: {
          """
          protocol AnalyticsProtocol: Sendable {
              func logEvent<E: Identifiable & Codable>(_ event: E)
          }

          struct AnalyticsProtocolWitness<A> {
              let logEvent: (A, any Identifiable & Codable) -> Void
          }
          """
        }
    }

}
