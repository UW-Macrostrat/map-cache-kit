//
//  MapboxUtils.swift
//  MobileMapCache
//
//  Created by Daven Quinn on 5/18/25.
//

import Foundation

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
        cacheType = .tile(x: x, y: y, z: z)
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

let imageExtensions = Set(["webp", "png", "jpg", "jpeg", "mvt", "pbf"])

enum CacheType {
  case tile(x: Int, y: Int, z: Int)
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
