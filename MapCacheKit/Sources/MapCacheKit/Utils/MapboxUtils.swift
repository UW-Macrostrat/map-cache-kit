//
//  MapboxUtils.swift
//  MapCacheKit
//
//  Created by Daven Quinn on 5/18/25.
//

import Foundation
import Vapor
import GEOSwift
import SwiftTileMatrix

func getMapboxCanonicalURL(_ url: String) -> CacheResourceInfo? {
  var matchURL = url

  let stylePrefix = "https://api.mapbox.com/styles/v1/"
  if matchURL.starts(with: stylePrefix) {
    matchURL = matchURL.replacingOccurrences(of: stylePrefix, with: "")
    var type: AssetType = .resource(.style)
    // We are dealing with a spriteJSON request
    // this is kind of a poor match, better to use a regex maybe
    // really we want to match strings that end with /sprite(@2x)?.(json|png)
    if matchURL.contains("/sprite") {
      matchURL = matchURL.replacingOccurrences(of: "/sprite", with: "")
      matchURL = "mapbox://sprites/" + matchURL
      if matchURL.hasSuffix(".json") {
        type = .resource(.spritejson)
      } else {
        type = .resource(.sprite)
      }
    } else {
      // This is a style request
      matchURL = "mapbox://styles/" + matchURL
    }
    return CacheResourceInfo(inputURL: url, templateURL: matchURL, type: type, thirdParty: false)
  }

  let fontsPrefix = "https://api.mapbox.com/fonts/v1/"
  if matchURL.starts(with: fontsPrefix) {
    // For some reason, we need to escape commas appropriately
    matchURL = matchURL.replacingOccurrences(of: ",", with: "%2c")
    return CacheResourceInfo(
      inputURL: url,
      templateURL: matchURL.replacingOccurrences(of: fontsPrefix, with: "mapbox://fonts/"),
      type: .resource(.font),
      thirdParty: false
    )
  }

  let tilePrefix = "https://api.mapbox.com/v4/"
  if matchURL.starts(with: tilePrefix) && matchURL.hasSuffix(".json") {
    // this is a source
    matchURL = matchURL.replacingOccurrences(of: ".json", with: "")
    return CacheResourceInfo(
      inputURL: url,
      templateURL: matchURL.replacingOccurrences(of: tilePrefix, with: "mapbox://"),
      type: .resource(.source),
      thirdParty: false
    )
  }

  // We are dealing with a tile request
  matchURL = matchURL.replacingOccurrences(of: tilePrefix, with: "mapbox://tiles/")
  let thirdParty = !matchURL.starts(with: "mapbox://")

  let ext = (matchURL as NSString).pathExtension

  let hasTileSuffix = imageExtensions.contains(ext)


  if !thirdParty || hasTileSuffix {
    // First-party tiles are never cached as webp
    if !thirdParty {
      matchURL = matchURL.replacingOccurrences(of: ".webp", with: ".png")
      matchURL = matchURL.replacingOccurrences(of: "@2x", with: "{ratio}")
    }
    // Replace values with templated string
    var cacheType: AssetType? = nil
    let range = NSRange(location: 0, length: matchURL.count)
    if let regex = try? NSRegularExpression(pattern: "/([0-9]+)/([0-9]+)/([0-9]+)"),
       let match = regex.firstMatch(in: matchURL, options: [], range: range) {
      var groups = match.groups(testedString: matchURL)
      let tileIndex = groups.removeFirst()
      if let z = Int(groups.removeFirst()),
         let x = Int(groups.removeFirst()),
         let y = Int(groups.removeFirst())
      {
        cacheType = .tile(TileIndex(x: x, y: y, z: z))
        matchURL = matchURL.replacingOccurrences(of: tileIndex, with: "/{z}/{x}/{y}")
      }
    }

    if let type = cacheType {
      return CacheResourceInfo(
        inputURL: url,
        templateURL: matchURL,
        type: type,
        thirdParty: thirdParty
      )
    }
  }
  return nil
}

func addSpriteSuffix(url: String) -> String {
  for ratio in ["@2x", ""] {
    for ext in [".png", ".json"] {
      let suffix = ratio + ext
      if url.hasSuffix(suffix) {
        return url.replacingOccurrences(of: suffix, with: "/sprite\(suffix)")
      }
    }
  }
  return url
}

func buildParams(_ params: [String: String?]) -> String? {
  guard !params.isEmpty else { return nil }
  var queryItems: [String] = []
  for (key, value) in params {
    let v1 = value?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
    if let val = v1 {
      queryItems.append("\(key)=\(val)")
    } else {
      queryItems.append("\(key)")
    }
  }
  return queryItems.joined(separator: "&")
}


let imageExtensions = Set(["webp", "png", "jpg", "jpeg", "mvt", "pbf"])

struct TileIndex: Hashable, Equatable, Sendable {
  let x: Int
  let y: Int
  let z: Int
  
  var tileCoord: TileCoord {
    return TileCoord(x, y, z)
  }
}



enum AssetType: Hashable, Equatable {
  case tile(TileIndex)
  case resource(ResourceKind)
}

struct CacheResourceInfo {
  let inputURL: String
  let templateURL: String
  let type: AssetType
  let thirdParty: Bool
}

extension NSTextCheckingResult {
  func groups(testedString:String) -> [String] {
    var groups = [String]()
    for i in  0 ..< self.numberOfRanges
    {
      let group = String(testedString[Range(self.range(at: i), in: testedString)!])
      groups.append(group)
    }
    return groups
  }
}

struct ResourceFindOptions {
  var maxCodePoint: Int = 65535 // Default to the maximum Unicode code point
}

func findResourcesRequestedByMapboxStyle(spec: StyleSpec, options: ResourceFindOptions = ResourceFindOptions()) throws -> Set<RequestedAsset> {
  var resources = Set<RequestedAsset>()

  // Find font stacks
  let fontStacks = try findFontStacksRequestedByMapboxStyle(spec: spec, maxCodePoint: options.maxCodePoint)
  resources.formUnion(fontStacks.map { RequestedAsset(urlTemplate: $0.urlTemplate, type: .resource(.font)) })

  // Find sprites
  let sprites = try findSpritesRequestedByMapboxStyle(spec: spec)
  resources.formUnion(sprites)

  // Find sources
  let sources = try findSourcesRequestedByMapboxStyle(spec: spec)
  resources.formUnion(sources)

  return resources
}



func findFontsRequestedByMapboxStyle(spec: StyleSpec) -> Set<String> {
  var fontStacks: Set<String> = []
  for lyr in spec.layers {
    if let font = lyr.layout?.textFont {
      switch font {
      case .constant(let fonts):
        // Concatenate fonts into a single font stack
        let fontStack = fonts.joined(separator: ",")
        fontStacks.insert(fontStack)
      case .expression(let value):
        // Traverse the expression to find any "literal" values
        // This may not get everything but it will be pretty good

        let literals = value.literals()

        for stack in literals {
          let val = stack.joined(separator: ",")
          fontStacks.insert(val)
        }
      }
    }
  }
  return fontStacks
}

func buildFontStackURL(_ urlTemplate: String, fontStack: String, range: String) -> String {
  // Encode the name of the font stack
  let encodedFontStack = fontStack.replacingOccurrences(of: " ", with: "%20")
    .replacingOccurrences(of: ",", with: "%2c")
    .replacingOccurrences(of: "/", with: "%2f")
    .replacingOccurrences(of: ":", with: "%3a")

  // Construct the URL for the font stack
  return urlTemplate
    .replacingOccurrences(of: "{fontstack}", with: encodedFontStack)
    .replacingOccurrences(of: "{range}", with: range)
}

func getFontStackURLs(_ styleSpec: StyleSpec, fontStacks: [String], ranges: [String] = ["0-255"]) -> [String] {
  var glyphsURLTemplate: String
  if let glyphs = styleSpec.glyphs {
    // Check if the glyphs URL is in the font stacks
    glyphsURLTemplate = glyphs
  } else if let owner = styleSpec.owner {
    // If the glyphs URL is not specified, use the owner to construct the URL
    glyphsURLTemplate = "mapbox://fonts/\(owner)/{fontstack}/{range}.pbf"
  } else {
    return []
  }

  var fontStackURLs: [String] = []
  for fontStack in fontStacks {
    for range in ranges {
      fontStackURLs.append(buildFontStackURL(glyphsURLTemplate, fontStack: fontStack, range: range))
    }
  }
  return fontStackURLs
}

func findFontStacksRequestedByMapboxStyle(spec: StyleSpec, maxCodePoint: Int = 65535) throws -> Set<RequestedAsset> {

  let fonts = Array(findFontsRequestedByMapboxStyle(spec: spec))

  var ranges: [String] = []
  // Go by ranges of 256 up to the max code point
  let _maxCodePoint = maxCodePoint - ((maxCodePoint + 1) % 256)

  if ((_maxCodePoint+1) % 256) != 0 {
    throw RuntimeError.invalidArgument("maxCodePoint must be one less than a multiple of 256")
  }
  for start in stride(from: 0, to: _maxCodePoint, by: 256) {
    ranges.append("\(start)-\(start + 255)")
  }

  var fontStacks = Set<RequestedAsset>()
  let fontStackURLs = getFontStackURLs(spec, fontStacks: fonts, ranges: ranges)

  for url in fontStackURLs {
    fontStacks.insert(RequestedAsset(urlTemplate: url, type: .resource(.font)))
  }

  return fontStacks
}

func findSpritesRequestedByMapboxStyle(spec: StyleSpec) throws -> Set<RequestedAsset> {
  var sprites = Set<RequestedAsset>()
  guard let sprite = spec.sprite else {
    return sprites
  }
  let kinds: [ResourceKind] = [.sprite, .spritejson]
  let suffixes = ["", "@2x"]

  // Iterate over each kind and suffix to generate the URLs
  for kind in kinds {
    let kindExt = kind == .sprite ? ".png" : ".json"
    for suffix in suffixes {
      let urlTemplate = sprite + suffix + kindExt
      sprites.insert(RequestedAsset(urlTemplate: urlTemplate, type: .resource(kind)))
    }
  }
  return sprites
}

func findSourcesRequestedByMapboxStyle(spec: StyleSpec) throws -> Set<RequestedAsset> {
  var sourceData: Set<RequestedAsset> = []

  for source in spec.sources.values {
    switch source.type {
    case .raster, .vector, .rasterDem, .geojson:
      if let url = source.url {
        sourceData.insert(RequestedAsset(urlTemplate: url, type: .resource(.source)))
      }
    default:
      break
    }
  }
  return sourceData
}

func buildCacheRegionThumbnailURL(app: Application, geometry: Geometry) throws -> URI {
  let staticMapStyle = try app.config.staticMapStyle
  guard let token = try app.config.mapboxAPIToken else {
    throw RuntimeError.configurationError("Mapbox API token is not set in the application config")
  }
  let baseURLTemplate = "\(staticMapStyle)/static/{position}/130x130@2x"
  let feat = Feature(geometry: geometry, properties: [
    "fill-color": "#0080ff", // blue color fill
    "fill-opacity": 0.2,
    "stroke": "#0080ff"
  ])

  let encFeat = try JSONEncoder().encode(feat)
  guard let overlay = String(data: encFeat, encoding: .utf8) else {
    throw RuntimeError.invalidArgument("Failed to encode position for thumbnail URL")
  }
  let overlay2 = overlay.replacingOccurrences(of: "\\.([0-9]{4})[0-9]+", with: ".$1", options: .regularExpression)
  let position = "geojson(\(overlay2))/auto"

  let baseURL = baseURLTemplate
    .replacingOccurrences(of: "{position}", with: position)
    .replacingOccurrences(of: "mapbox://styles", with: "/styles/v1")

  return URI(
    scheme: "https",
    host: "api.mapbox.com",
    path: baseURL,
    query: buildParams(["access_token": token])
  )
}
