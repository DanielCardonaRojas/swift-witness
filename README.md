# Witness: Protocol Witness Macro for Swift 🛡️

[![Swift Version](https://img.shields.io/badge/Swift-5.9-orange.svg)]()
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/Version-0.1.0-brightgreen.svg)]()
[![CI Status](https://github.com/DanielCardonaRojas/ProtocolWitnessMacro/actions/workflows/pull_request.yml/badge.svg)](https://github.com/DanielCardonaRojas/ProtocolWitnessMacro/actions/workflows/pull_request.yml)

**Witness** is a Swift package that provides a macro to generate protocol witness structs from protocol declarations. This allows you to create lightweight, composable, and dynamic representations of protocol conformances, enabling powerful abstractions and transformations.

---

## ✨ Features

-   **🔄 Transform Methods**: Automatically generates utility methods like `pullback`, `map`, and `iso` for transforming witness structs.
-   **🤝 Conformance Initializer**: Generates a special initializer that converts a protocol conformance into a witness struct.
-   **⚙️ Dynamic Code Generation**: The macro generates code dynamically based on the options you supply, ensuring flexibility and adaptability.
-   **⚡ Synthesized Conformances**: Automatically synthesizes a protocol conformance from a witness, enabling powerful dynamic behavior.
-   **✅ Comprehensive Protocol Support**: Supports a wide range of protocol features, including:
    -   Associated types
    -   Subscripts
    -   Async/await functions
    -   Getters and setters
    -   Mutating functions

---

## 📦 Installation

To use **Witness** in your project, add it as a dependency in your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/DanielCardonaRojas/ProtocolWitnessMacro.git", from: "0.1.0")
]
```

Then, import the package in your Swift files:

```swift
import Witness
```

---

## 🚀 Usage

### Basic Example

To generate a witness struct for a protocol, simply annotate the protocol with the `@Witnessed` macro:

```swift
@Witnessed([.utilities])
public protocol Comparable {
    func compare(_ other: Self) -> Bool
}
```

<details> <summary>Generated Code</summary>

```swift
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
```

</details>

### Advanced Example

```swift
@Witnessed([.conformanceInit, .utilities])
public protocol Snapshottable {
    associatedtype Format: Diffable
    static var pathExtension: String { get }
    var snapshot: Format { get }
}
```

<details> <summary>Generated Code</summary>

```swift
public struct SnapshottableWitness<A, Format> {
    public let diffable: DiffableWitness<Format>
    public let pathExtension: () -> String
    public let snapshot: (A) -> Format

    public init(
        diffable: DiffableWitness<Format>,
        pathExtension: @escaping () -> String,
        snapshot: @escaping (A) -> Format
    ) {
        self.diffable = diffable
        self.pathExtension = pathExtension
        self.snapshot = snapshot
    }

    public init() where A: Snapshottable, Format: Diffable, A.Format == Format {
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
```

</details>

---

## 🤔 What is a protocol witness?

> A protocol witness is a concrete type (typically a struct) that implements the requirements of a protocol. Instead of a type conforming to a protocol directly, a "witness" is created that holds a set of closures, where each closure corresponds to a requirement of the protocol. This approach, popularized by the [Point-Free](https://www.pointfree.co) video series, allows for greater flexibility and composability.

For a detailed explanation, watch Brandon Williams' talk on the subject:
[Protocol Witnesses by Brandon Williams (Point-Free)](https://www.youtube.com/watch?v=clP_r_20p2A)

For more reading, check out this article:
[Protocol Witnesses in Swift by Jean Ruiz](https://jeansruiz.com/protocols/2023/04/28/protocol-witnesses.html)

---

## 🛠️ Supported Protocol Features

| Feature                  | Done       | In Progress |
| ------------------------ | ---------- | ----------- |
| Associated Types         | ✅          |             |
| Subscripts               | ✅          |             |
| Async/Await              | ✅          |             |
| Getters/Setters          | ✅          |             |
| Mutating Functions       | ✅          |             |
| Implicit `self` Mapping  | ✅          |             |

### Implicit `self` Mapping

For non-static methods, the implicit `self` parameter is mapped to the first parameter in the generated closure. For example:

Here, the `self` parameter in the `toggle()` method is mapped to the `inout A` parameter in the closure.

---

## 📚 Other Examples

### `RandomNumberGenerator`

```swift
@Witnessed([.utilities])
protocol RandomNumberGenerator {
    func random() -> Double
}
```

<details> <summary>Generated Code</summary>

```swift
struct RandomNumberGeneratorWitness<A> {
    let random: (A) -> Double
    init(
        random: @escaping (A) -> Double
    ) {
        self.random = random
    }
    func transform<B>(
        pullback: @escaping (B) -> A
    ) -> RandomNumberGeneratorWitness<B> {
        .init(
            random: {
                self.random(pullback($0))
            }
        )
    }
}
```

</details>

### `Togglable`

```swift
@Witnessed()
protocol Togglable {
    mutating func toggle()
}
```

<details> <summary>Generated Code</summary>

```swift
struct TogglableWitness<A> {
    let toggle: (inout A) -> Void
    init(
        toggle: @escaping (inout A) -> Void
    ) {
        self.toggle = toggle
    }
}
```

</details>

### `Convertible`

```swift
@Witnessed([.utilities, .conformanceInit])
protocol Convertible {
    associatedtype To
    func convert() -> To
}
```

<details> <summary>Generated Code</summary>

```swift
struct ConvertibleWitness<A, To> {
    let convert: (A) -> To
    init(
        convert: @escaping (A) -> To
    ) {
        self.convert = convert
    }
    init() where A: Convertible, A.To == To {
        self.convert = { instance in
            instance.convert()
        }
    }
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
```

</details>

---

## 📄 License

**Witness** is released under the MIT License. See [LICENSE](LICENSE) for details.
