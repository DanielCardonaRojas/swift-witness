//
//  File.swift
//  
//
//  Created by Daniel Cardona on 28/03/24.
//

extension Combining where A: Combinable {
  init() {
    self.combine = { this, other in
      this.combine(other)
    }
  }
}

extension Combining where A: Numeric {
  static var sum: Combining {
    return Combining { $0 + $1 }
  }
  
  static var prod: Combining {
    return Combining { $0 + $1 }
  }
}

extension Combining where A: RangeReplaceableCollection {
  static var concat: Combining {
    return Combining { $0 + $1 }
  }
}

extension Array {
  func reduce(_ initial: Element, _ combining: Combining<Element>) -> Element {
    return self.reduce(initial, combining.combine)
  }
}
