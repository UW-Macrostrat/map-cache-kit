//
//  MapCacheServer.swift
//  App
//
//  Created by Daven Quinn on 4/23/22.
//

import Foundation
import GCDWebServer
import Turf
import GRDB

enum MapCachePriority: String {
  case cache = "cache"
  case network = "network"
  case cacheThenNetwork = "cache-then-network"
}

func ErrorResponse(_ message: String, statusCode: Int = 500)->GCDWebServerResponse {
  let data = Data((message).utf8)
  let resp = GCDWebServerDataResponse(data: data, contentType: "text/plain")
  resp.statusCode = statusCode
  resp.setValue("*", forAdditionalHeader: "Access-Control-Allow-Origin")
  return resp
}

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

extension String {
  func removingRegexMatches(pattern: String, replaceWith: String = "")->String {
    do {
      let regex = try NSRegularExpression(pattern: pattern)
      let range = NSRange(location: 0, length: count)
      return regex.stringByReplacingMatches(in: self, options: [], range: range, withTemplate: replaceWith)
    } catch {
      return self
    }
  }
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


let imageExtensions = Set(["webp", "png", "jpg", "jpeg", "mvt", "pbf"])

class MapCacheServer: NSObject {
  
  static let shared = MapCacheServer()
  private var webServer: GCDWebServer? = nil
  var defaultDomain = "https://api.mapbox.com"
  var port: UInt = 50051
  var cacheMode: MapCachePriority = .cacheThenNetwork
  
  private var dynamicStyles: [String: [String: Any]] = [:]
  
  
  // MARK: Functions
  
  func start() {
    // This is kinda scary and we should really rethink this
    guard Thread.isMainThread else {
      DispatchQueue.main.sync { [weak self] in
        self?.start()
      }
      return
    }
    
    if self.webServer != nil {
      return
    }
    
    self.webServer = GCDWebServer()
    
    /* This web server routes all requests to Mapbox's APIs, so we can intercept some and grab data
     from a local cache as appropriate.
     */
    
    // Log Level 0 is debug mode, Log Level 4 is error (somewhat counterintuitively)
    GCDWebServer.setLogLevel(4)
    
    webServer!.addDefaultHandler(
      forMethod: "GET",
      request: GCDWebServerRequest.self,
      asyncProcessBlock: { request, completion in
        
        var query = request.query
        
        let cacheDomain = query?.removeValue(forKey: "x-cache-domain") ?? request.headers["x-cache-domain"]
        
        if request.path.starts(with: "/dynamic-styles/") && cacheDomain == nil {
          return completion(self.handleDynamicStyleRequest(request))
        }
        
        // return completion(ErrorResponse("Invalid method", statusCode: 500))
        
        // Get the domain to use for the response
        let domain = cacheDomain ?? self.defaultDomain
        let pth = request.url.path.replacingOccurrences(of: " ", with: "%20")
        
        guard
          let domainURL = URL(string: domain),
          let url1 = URL(string: pth, relativeTo: domainURL),
          var urlBase = URLComponents(string: url1.absoluteString)
        else {
          return completion(ErrorResponse("Could not decode URL", statusCode: 500))
        }
        
        if self.cacheMode != .network {
          let cachedResponse = self.assembleLocalResponse(for: url1)
          if let res = cachedResponse {
            print("Cache hit:", domain, url1.absoluteString)
            return completion(res)
          }
        }
        
        // We are now falling back to network requests.
        if self.cacheMode == .cache {
          return completion(ErrorResponse("Resource not in cache", statusCode: 404))
        }
        
        // Add query parameters to URL
        if let q = query {
          urlBase.queryItems = q.map { (key, value) in URLQueryItem(name: key, value: value) }
        }
        guard let url = urlBase.url else {
          return completion(ErrorResponse("Could not decode URL", statusCode: 500))
        }
        
        
        let resp = GCDWebServerResponse(redirect: url.absoluteURL, permanent: false)
        resp.setValue("http://localhost:\(self.port)", forAdditionalHeader: "Origin")
        resp.setValue("*", forAdditionalHeader: "Access-Control-Allow-Origin")
        resp.setValue("miss", forAdditionalHeader: "x-cache")
        
        return completion(resp)
      }
    )
    
    webServer!.start(withPort: self.port, bonjourName: nil)
    
  }
  
  func handleDynamicStyleRequest(_ request: GCDWebServerRequest)-> GCDWebServerResponse {
    let styleID = request.path
      .replacingOccurrences(of: "/dynamic-styles/", with: "")
      .replacingOccurrences(of: ".json", with: "")
    guard let data = self.dynamicStyles[styleID] else {
      return ErrorResponse("Could not find the requested dynamic style.")
    }
    return GCDWebServerDataResponse(jsonObject: data) ?? ErrorResponse("Could not parse JSON style")
  }
  
  func assembleLocalResponse(for url: URL)->GCDWebServerResponse? {
    do {
      var data = try MapCacheManager.shared.getTileFromDatabase(url: url.absoluteURL)
      
      if (data == nil) {
        data = try MapCacheManager.shared.getTileFromDatabase(url: url.absoluteURL, forceDownscale: true)
      }
      
      if let d = data {
        return ServerResponse(for: d)
      } else {
        return nil
      }
    } catch let err {
      if self.cacheMode == .cache {
        return ErrorResponse(message(for: err), statusCode: 404)
      }
    }
    return nil
  }
  
  func stop() {
    guard Thread.isMainThread else {
      DispatchQueue.main.sync { [weak self] in
        self?.stop()
      }
      return
    }
    webServer?.stop()
    webServer?.removeAllHandlers()
  }
  
  // Dynamic tile layers
  func registerDynamicStyle(for id: String, with data: [String: Any]) {
    self.dynamicStyles[id] = data
  }
}

func ServerResponse(for data: TileResponse)->GCDWebServerDataResponse {
  let ctype = data.contentType ?? "text/plain"
  let res = GCDWebServerDataResponse(data: data.data, contentType: ctype)
  res.setValue("*", forAdditionalHeader: "Access-Control-Allow-Origin")
  res.setValue("hit", forAdditionalHeader: "x-cache")
  if (data.compressed) {
    res.setValue("deflate", forAdditionalHeader: "Content-Encoding")
  }
  return res
}
