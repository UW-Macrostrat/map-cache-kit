import Foundation
import GEOSwift

enum Argument<T: Codable>: Codable {
  case string(String)
  case integer(Int)
  case number(Double)
  case boolean(Bool)
  case literal(T)
  case expression(Expr<T>)
  
  func unwrap() -> T? {
    switch self {
    case .string(let value):
      return value as? T
    case .integer(let value):
      return value as? T
    case .number(let value):
      return value as? T
    case .boolean(let value):
      return value as? T
    case .literal(let value):
      return value
    case .expression(let expr):
      if case let .literal(value) = expr {
        return value as T
      } else {
        return nil
      }
    }
  }
  
  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode(Int.self) {
      self = .integer(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(Bool.self) {
      self = .boolean(value)
    } else if let value = try? container.decode(T.self) {
      self = .literal(value)
    } else {
      let expr = try container.decode(Expr<T>.self)
      self = .expression(expr)
    }
  }

}

enum Expr<T: Codable>: Codable {
  case literal(T)
  case zoom
  case other(name: String, arguments: [Argument<T>])
  
  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    // Decode as an array of arguments
    let array = try container.decode([Argument<T>].self)
    
    guard array.count >= 1 else {
       throw DecodingError.typeMismatch(Expr.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected an array"))
    }
    
    if array.count == 1 {
      // The only single-argument expression is "zoom"
      guard case .string("zoom") = array[0] else {
        throw DecodingError.typeMismatch(Expr.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected single argument to be 'zoom'"))
      }
      
      self = .zoom
      return
    }
    
    // Ensure that the first argument decodes as a string
    guard case let .string(name) = array[0] else {
      throw DecodingError.typeMismatch(Expr.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected first argument to be a string"))
    }
    
    if (name == "literal") {
      // If the first argument is "literal", decode the second argument as the literal value
      guard array.count == 2 else {
        throw DecodingError.typeMismatch(Expr.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected exactly two arguments for 'literal' expression"))
      }
      guard let literalValue = array[1].unwrap() else {
        throw DecodingError.typeMismatch(Expr.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected second argument to of the proper type"))
      }
      
      self = .literal(literalValue)
    } else {
      // Otherwise, treat it as a function call with name and arguments
      let args = Array(array.dropFirst())
      self = .other(name: name, arguments: args)
    }
  }
  
  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .literal(let value):
      try container.encode([Argument<T>.expression(.literal(value))])
    case .zoom:
      try container.encode([Argument<T>.string("zoom")])
    case .other(let name, let arguments):
      var args = [Argument<T>.string(name)]
      args.append(contentsOf: arguments)
      try container.encode(args)
    }
  }
}

extension Expr where T: Codable {
  func literals() -> [T] {
    // Accumulate all literal values from the expression
    var results = [T]()
    
    func traverse(_ expr: Expr<T>) {
      switch expr {
      case .literal(let value):
        results.append(value)
      case .zoom:
        // Zoom does not have a literal value
        break
      case .other(_, let arguments):
        for arg in arguments {
          if case let .expression(innerExpr) = arg {
            traverse(innerExpr)
          }
        }
      }
    }
    
    traverse(self)
    
    return results
  }
}

enum Value<T: Codable>: Codable {
  case constant(T)
  case expression(Expr<T>)
  
  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let value = try? container.decode(T.self) {
      self = .constant(value)
    } else {
      let expr = try container.decode(Expr<T>.self)
      self = .expression(expr)
    }
  }
  
  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .constant(let value):
      try container.encode(value)
    case .expression(let expr):
      try container.encode(expr)
    }
  }
}



struct StyleSpec: Codable {
  /** A partial spec for decoding styles */
  let version: Int
  let sources: [String: StyleSource]
  let layers: [StyleLayer]
  let glyphs: String?
  let sprite: String?
  let owner: String?

  struct StyleSource: Codable {
    let type: SourceType
    let tiles: [String]?
    let url: String?
  }
  
  struct StyleLayer: Codable {
    let id: String
    let type: String
    let source: String?
    let sourceLayer: String?
    let layout: StyleLayout?
    let paint: StylePaint?
    
    struct StyleLayout: Codable {
      let textFont: Value<[String]>?
      let visibility: Value<String>?
      
      enum CodingKeys: String, CodingKey {
        case textFont = "text-font"
        case visibility
      }
    }
    
    struct StylePaint: Codable {
      let backgroundColor: JSON?
      let textColor: JSON?
      
      enum CodingKeys: String, CodingKey {
        case backgroundColor = "background-color"
        case textColor = "text-color"
      }
    }
  }
}
