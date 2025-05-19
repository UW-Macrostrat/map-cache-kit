//
//  CachedTileController.swift
//  MobileMapCache
//
//  Created by Daven Quinn on 5/18/25.
//
import Fluent
import Vapor
import FluentSQL

struct CachedTileController: RouteCollection {
  let cacheMode: MapCachePriority
  
  func boot(routes: any RoutesBuilder) throws {
    let tiles = routes.grouped("tiles")
    
    tiles.get(use: self.index)
  }
  
  @Sendable
  func index(req: Request) async throws -> Response {
    let cacheDomain = req.headers["x-cache-domain"] ?? "https://api.mapbox.com"
    
    // Get path from query argument
    guard let path: String = try req.query.get(at: "path") else {
      throw Abort(.badRequest, reason: "No cache path provided")
    }
    let p1 = path.replacingOccurrences(of: " ", with: "%20")
    
    guard let domainURL = URL(string: cacheDomain),
          let url1 = URL(string: p1, relativeTo: domainURL),
          var urlBase = URLComponents(string: url1.absoluteString)
    else {
      throw Abort(.badRequest, reason: "Could not decode URL")
    }
        
    if self.cacheMode != .network {
      let cachedResponse = self.assembleLocalResponse(for: url1)
      if let res = cachedResponse {
        print("Cache hit:", domain, url1.absoluteString)
        return completion(res)
      }
    }
    
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
}

enum MapCachePriority: String {
  case cache = "cache"
  case network = "network"
  case cacheThenNetwork = "cache-then-network"
}

/**
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
 
 */
