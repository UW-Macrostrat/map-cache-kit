//
//  CachedTileController.swift
//  MapCacheKit
//
//  Created by Daven Quinn on 5/18/25.
//
import Fluent
import Vapor
import FluentSQL

typealias QueryParams = [
  String: String?
]

struct CachedTileController: RouteCollection {
  func boot(routes: any RoutesBuilder) throws {
    let tiles = routes.grouped("tiles")

    tiles.get("**", use: self.catchAll)
  }

  @Sendable
  func catchAll(req: Request) async throws -> Response {

    let path = req.parameters.getCatchall().joined(separator: "/")

    // get all query parametrs
    guard var queryParams = try? req.query.decode(QueryParams.self) else {
      throw Abort(.badRequest, reason: "Could not decode query parameters")
    }

    func getQueryParam(_ key: String, _ defaultValue: String) -> String {
      guard let val = queryParams.removeValue(forKey: key) else {
        return defaultValue
      }
      return val ?? defaultValue
    }


    guard let q1 = queryParams.removeValue(forKey: "x-cache-domain"),
      var cacheDomain = q1 else {
      throw Abort(.badRequest, reason: "Missing x-cache-domain parameter")
    }

    let cacheScheme = getQueryParam("x-cache-scheme", "https")

    guard let cacheMode = MapCachePriority(rawValue: getQueryParam("x-cache-mode", "cache-then-network").lowercased()) else {
      throw Abort(.badRequest, reason: "Invalid cache mode")
    }

    if !cacheDomain.hasPrefix("https://") && !cacheDomain.hasPrefix("http://") {
      cacheDomain = "\(cacheScheme)://\(cacheDomain)"
    }

    guard let domainURL = URL(string: cacheDomain),
      let url1 = URL(string: path, relativeTo: domainURL)
    else {
      throw Abort(.badRequest, reason: "Could not decode URL")
    }

    guard let db = req.db as? any SQLDatabase else {
      throw Abort(.internalServerError, reason: "Database is not SQLDatabase")
    }

    // Raster URL does not support OPTIONS requests
    if cacheMode != .network {
      if let cachedResponse = try await getCachedResource(from: db, url: url1) {
        let res = Response(status: .ok, headers: [
          "Content-Type": cachedResponse.contentType ?? "application/x-protobuf",
          "Cache-Control": "public, max-age=31536000",
          "X-Cache": "hit",
        ], body: .init(data: cachedResponse.data))

        if let encoding = compressionAlgorithm(for: cachedResponse.data) {
          res.headers.add(name: "Content-Encoding", value: encoding)
        }

        return res
      } else if cacheMode == .cache {
        throw Abort(.notFound, reason: "Cache miss")
      }
    }
    // If in cache-then-network mode without a tile, or in network mode, we need to redirect
    // to the original URL

    // Add query parameters to URL
    let urlOut: URL
    if queryParams.isEmpty {
      urlOut = url1
    } else {
      guard var url2 = URLComponents(string: url1.absoluteString) else {
        throw Abort(.badRequest, reason: "Could not decode URL")
      }
      url2.queryItems = (url2.queryItems ?? []) + queryParams.map { (key, value) in URLQueryItem(name: key, value: value) }
      guard let url3 = url2.url else {
        throw Abort(.badRequest, reason: "Could not decode URL")
      }
      urlOut = url3
    }
    return req.redirect(to: urlOut.absoluteString, redirectType: .temporary)
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

func getCacheMode(req: Request) throws -> MapCachePriority {
  guard let cacheMode = req.headers.first(name: "x-cache-mode") else {
    return .cacheThenNetwork
  }

  let mode = MapCachePriority(rawValue: cacheMode.lowercased())
  if let mode = mode {
    return mode
  }
  throw Abort(.badRequest, reason: "Invalid cache mode \(cacheMode)")
}


func getCachedResource(from db: any SQLDatabase, url: URL, forceDownscale: Bool = false) async throws -> TileResponse? {
  let matchParams = getMapboxCanonicalURL(url.absoluteString)
  //
  //    if forceDownscale {
  //      // If we are not online, we want to load anything we can grab, so we force tiles to downscale.
  //      matchURL = matchURL.replacingOccurrences(of: "@2x", with: "")
  //    }

  guard let params = matchParams else {
    return nil
  }
  
  let path = params.templateURL

  let sql: SQLQueryString

  switch params.type {
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
    url: params.inputURL,
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
  // Mapbox resource types
  case style = 1
  case source = 2
  case font = 4
  case sprite = 5
  case spritejson = 6
  // our resource types
  case thumbnail = -100
}
