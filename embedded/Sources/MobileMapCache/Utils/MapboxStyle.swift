import Foundation

enum AnyCodable: Codable {
  case string(String)
  case int(Int)
  case double(Double)
  case bool(Bool)
  case array([AnyCodable])
  case dictionary([String: AnyCodable])
  
  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    
    if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode(Int.self) {
      self = .int(value)
    } else if let value = try? container.decode(Double.self) {
      self = .double(value)
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode([AnyCodable].self) {
      self = .array(value)
    } else if let value = try? container.decode([String: AnyCodable].self) {
      self = .dictionary(value)
    } else {
      throw DecodingError.typeMismatch(AnyCodable.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported type"))
    }
  }
  
  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    
    switch self {
    case .string(let value):
      try container.encode(value)
    case .int(let value):
      try container.encode(value)
    case .double(let value):
      try container.encode(value)
    case .bool(let value):
      try container.encode(value)
    case .array(let value):
      try container.encode(value)
    case .dictionary(let value):
      try container.encode(value)
    }
  }
}

typealias Expr = AnyCodable

enum Value<T: Codable>: Codable {
  case constant(T)
  case expression(Expr)
  
  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let value = try? container.decode(T.self) {
      self = .constant(value)
    } else {
      self = .expression(try container.decode(Expr.self))
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
  
  struct StyleSource: Codable {
    let type: String
    let tiles: [String]?
    let url: String?
  }
  
  struct StyleLayer: Codable {
    let id: String
    let type: String
    let source: String?
    let sourceLayer: String?
    let layout: StyleLayout
    let paint: StylePaint
    
    struct StyleLayout: Codable {
      let textFont: Value<[String]>?
      let visibility: Value<String>?
      
      enum CodingKeys: String, CodingKey {
        case textFont = "text-font"
        case visibility
      }
    }
    
    struct StylePaint: Codable {
      let backgroundColor: String?
      let textColor: String?
      
      enum CodingKeys: String, CodingKey {
        case backgroundColor = "background-color"
        case textColor = "text-color"
      }
    }
  }
}
