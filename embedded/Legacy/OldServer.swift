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
