//
//  MapboxUtils.swift
//  MobileMapCache
//
//  Created by Daven Quinn on 5/18/25.
//

import Foundation
import Vapor
import GEOSwift

func getMapboxCanonicalURL(_ url: String)-> CacheResourceInfo {
  var matchURL = url
  
  let stylePrefix = "https://api.mapbox.com/styles/v1/"
  if matchURL.starts(with: stylePrefix) {
    matchURL = matchURL.replacingOccurrences(of: stylePrefix, with: "")
    // We are dealing with a spriteJSON request
    // this is kind of a poor match, better to use a regex maybe
    // really we want to match strings that end with /sprite(@2x)?.(json|png)
    if matchURL.contains("/sprite") {
      matchURL = matchURL.replacingOccurrences(of: "/sprite", with: "")
      matchURL = "mapbox://sprites/" + matchURL
    } else {
      // This is a style request
      matchURL = "mapbox://styles/" + matchURL
    }
    return CacheResourceInfo(inputURL: url, templateURL: matchURL, cacheType: .resource, thirdParty: false)
  }
  
  let fontsPrefix = "https://api.mapbox.com/fonts/v1/"
  if matchURL.starts(with: fontsPrefix) {
    // For some reason, we need to escape commas appropriately
    matchURL = matchURL.replacingOccurrences(of: ",", with: "%2c")
    return CacheResourceInfo(
      inputURL: url,
      templateURL: matchURL.replacingOccurrences(of: fontsPrefix, with: "mapbox://fonts/"),
      cacheType: .resource,
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
      cacheType: .resource,
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
    var cacheType: CacheType? = nil
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
        cacheType: type,
        thirdParty: thirdParty
      )
    }
  }
  
  return CacheResourceInfo(
    inputURL: url,
    templateURL: url,
    cacheType: .resource,
    thirdParty: thirdParty
  )
}

func getDownloadURL(tile: CandidateTile, params: [String: String?] = [:]) -> URI {
  var tileURL = tile.urlTemplate
    .replacingOccurrences(of: "{z}", with: "\(tile.z)")
    .replacingOccurrences(of: "{x}", with: "\(tile.x)")
    .replacingOccurrences(of: "{y}", with: "\(tile.y)")
    .replacingOccurrences(of: "{ratio}", with: "@2x")
    .replacingOccurrences(of: "mapbox://tiles", with: "https://api.mapbox.com/v4")
  
  // Replace webp
  if tileURL.hasSuffix(".webp") {
    tileURL = tileURL.replacingOccurrences(of: ".webp", with: ".png")
  }
  
  var uri = URI(string: tileURL)
  uri.query = buildParams(params)
  return uri
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

func getDownloadURL(_ resource: RequestedResource, params: [String: String?] = [:]) -> URI {
  var resourceURL = resource.urlTemplate
  if resourceURL.hasPrefix("mapbox://fonts/") {
    resourceURL = resourceURL.replacingOccurrences(of: "mapbox://fonts/", with: "https://api.mapbox.com/fonts/v1/")
  } else if resourceURL.hasPrefix("mapbox://sprites/") {
    resourceURL = resourceURL.replacingOccurrences(of: "mapbox://sprites/", with: "https://api.mapbox.com/styles/v1/")
    resourceURL = addSpriteSuffix(url: resourceURL)
  } else if resourceURL.hasPrefix("mapbox://styles/") {
    resourceURL = resourceURL.replacingOccurrences(of: "mapbox://styles/", with: "https://api.mapbox.com/styles/v1/")
  } else if resourceURL.hasPrefix("mapbox://tiles/") {
    resourceURL = resourceURL.replacingOccurrences(of: "mapbox://tiles/", with: "https://api.mapbox.com/v4/")
  } else if resourceURL.hasPrefix("mapbox://") {
    // A tileset
    resourceURL = resourceURL.replacingOccurrences(of: "mapbox://", with: "https://api.mapbox.com/v4/")
    resourceURL += ".json"
  }
  

  var uri = URI(string: resourceURL)
  // Encode URL parameters if provided
  uri.query = buildParams(params)
  return uri
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

struct TileIndex {
  let x: Int
  let y: Int
  let z: Int
}

enum CacheType {
  case tile(TileIndex)
  case resource
}

struct CacheResourceInfo {
  let inputURL: String
  let templateURL: String
  let cacheType: CacheType
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

func findResourcesRequestedByMapboxStyle(spec: StyleSpec, options: ResourceFindOptions = ResourceFindOptions()) throws -> Set<RequestedResource> {
  var resources = Set<RequestedResource>()
  
  // Find font stacks
  let fontStacks = try findFontStacksRequestedByMapboxStyle(spec: spec, maxCodePoint: options.maxCodePoint)
  resources.formUnion(fontStacks.map { RequestedResource(urlTemplate: $0.urlTemplate, kind: .font) })
  
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

func findFontStacksRequestedByMapboxStyle(spec: StyleSpec, maxCodePoint: Int = 65535) throws -> Set<RequestedResource> {
  
  let fonts = Array(findFontsRequestedByMapboxStyle(spec: spec))
  
  var ranges: [String] = []
  // Go by ranges of 256 up to the max code point
  for start in stride(from: 0, to: maxCodePoint, by: 256) {
    let end = min(start + 255, maxCodePoint)
    ranges.append("\(start)-\(end)")
  }

  var fontStacks = Set<RequestedResource>()
  let fontStackURLs = getFontStackURLs(spec, fontStacks: fonts, ranges: ranges)
  
  for url in fontStackURLs {
    fontStacks.insert(RequestedResource(urlTemplate: url, kind: .font))
  }
  
  return fontStacks
}

func findSpritesRequestedByMapboxStyle(spec: StyleSpec) throws -> Set<RequestedResource> {
  var sprites = Set<RequestedResource>()
  
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
      sprites.insert(RequestedResource(urlTemplate: urlTemplate, kind: kind))
    }
  }

  return sprites
}

func findSourcesRequestedByMapboxStyle(spec: StyleSpec) throws -> Set<RequestedResource> {
  var sourceData: Set<RequestedResource> = []
  
  for source in spec.sources.values {
    switch source.type {
    case .raster, .vector, .rasterDem, .geojson:
      if let url = source.url {
        sourceData.insert(RequestedResource(urlTemplate: url, kind: .source))
      }
    default:
      break
    }
  }
  
  return sourceData
}

func buildCacheRegionThumbnailURL(app: Application, region: MBXCacheRegion) throws -> String? {
  if region.isGlobal {
    return nil // No thumbnail for global regions
  }
  
  let staticMapStyle = try app.config.staticMapStyle
  let baseURLTemplate = "\(staticMapStyle)/static/"
  
  let geom = try region.getGeometry()
  
  let feat = Feature(geometry: geom, properties: [
    "fill-color": "#0080ff", // blue color fill
    "fill-opacity": 0.2,
    "stroke": "#0080ff"
  ])
  
  let encFeat = try JSONEncoder().encode(feat)
  guard let overlay = String(data: encFeat, encoding: .utf8)?.replacingOccurrences(of: "#", with: "%23").replacingOccurrences(of: " ", with: "") else {
    throw RuntimeError.invalidArgument("Failed to encode position for thumbnail URL")
  }
  
  // truncate precision to 4 decimal places
  let overlay2 = overlay.replacingOccurrences(of: "\\.([0-9]{4})[0-9]+", with: ".$1", options: .regularExpression)
  
  let position = "geojson(\(overlay2))/auto"
  // convert geometry to geojson
  
  let baseURL = baseURLTemplate.replacingOccurrences(of: "mapbox://styles", with: "https://api.mapbox.com/styles/v1")

  return baseURL + position + "/130x130@2x"
}
