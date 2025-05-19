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
    
    guard let cacheDomain = req.headers.first(name: "x-cache-domain") else {
      throw Abort(.badRequest, reason: "No cache domain provided")
    }
    
    // Get path from query argument
    guard let path: String = try req.query.get(at: "x-cache-path") else {
      throw Abort(.badRequest, reason: "No cache path provided")
    }
    let p1 = path.replacingOccurrences(of: " ", with: "%20")
    
    guard let domainURL = URL(string: cacheDomain),
          let url1 = URL(string: p1, relativeTo: domainURL)
    else {
      throw Abort(.badRequest, reason: "Could not decode URL")
    }
    
    guard let db = req.db as? any SQLDatabase else {
      throw Abort(.internalServerError, reason: "Database is not SQLDatabase")
    }
        
    if self.cacheMode != .network {
      if let cachedResponse = try await getCachedResource(from: db, url: url1) {
        return Response(status: .ok, headers: [
          "Content-Type": cachedResponse.contentType ?? "application/x-protobuf",
          "Cache-Control": "public, max-age=31536000",
          "X-Cache": "hit",
        ], body: .init(data: cachedResponse.data))
      } else if self.cacheMode == .cache {
        throw Abort(.notFound, reason: "Cache miss")
      }
    }
    // If in cache-then-network mode without a tile, or in network mode, we need to redirect
    // to the original URL
    
    // Add query parameters to URL
    var urlBase = URLComponents(string: url1.absoluteString)
    
    return Response(status: .temporaryRedirect, headers: [
      "Location": url1.absoluteString,
      "X-Cache": self.cacheMode == .network ? "bypass" : "miss",
    ], body: .empty)
  }
}

enum MapCachePriority: String {
  case cache = "cache"
  case network = "network"
  case cacheThenNetwork = "cache-then-network"
}

struct ResourceRow: Content {
  let data: Data
  let url: String
  let compressed: Bool
}
  

func getCachedResource(from db: any SQLDatabase, url: URL, forceDownscale: Bool = false) async throws -> TileResponse? {
  let matchParams = getMapboxCanonicalURL(url.absoluteString)
  //
  //    if forceDownscale {
  //      // If we are not online, we want to load anything we can grab, so we force tiles to downscale.
  //      matchURL = matchURL.replacingOccurrences(of: "@2x", with: "")
  //    }
    
  let path = matchParams.templateURL

  let sql: SQLQueryString
  
  switch matchParams.cacheType {
  case .tile(let tileIndex):
    sql = """
    SELECT
     data,
     url_template url,
     compressed
    FROM tiles
    WHERE (url_template = \(bind: path)
       OR url_template = replace(\(bind: path), '{ratio}', '@2x')
       OR url_template = replace(\(bind: path), '{ratio}', ''))
      AND x = \(bind: tileIndex.x)
      AND y = \(bind: tileIndex.y)
      AND z = \(bind: tileIndex.z)
    LIMIT 1
    """
  case .resource:
    sql = """
    SELECT
      data,
      url,
      kind,
      compressed
    FROM resources
    WHERE url = \(bind: path)
    LIMIT 1
    """
  }

  let row = try await db.raw(sql).first(decoding: ResourceRow.self)
  
  guard let res = row else {
    return nil
  }
  
  let uuid = UUID()
  let response = TileResponse(
    data: res.data,
    compressed: res.compressed,
    url: matchParams.inputURL,
    urlTemplate: res.url,
    uuid: uuid,
    contentType: ctypeIndex[url.pathExtension]
  )
  return response
}

struct TileResponse {
  let data: Data
  let compressed: Bool
  let url: String
  let urlTemplate: String
  let uuid: UUID
  let contentType: String?
}

let ctypeIndex = [
  "png": "image/png",
  "webp": "image/png",
  "vrt": "application/x-protobuf",
  "json": "application/json",
  "mvt": "application/x-protobuf",
  "pbf": "application/x-protobuf",
  "geojson": "application/json",
]

enum ResourceKind: Int {
  case style = 1
  case source = 2
  case font = 4
  case sprite = 5
  case spritejson = 6
}
