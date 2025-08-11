//
//  CacheRegionsController.swift
//  MobileMapCache
//
//  Created by Daven Quinn on 5/17/25.
//

import Fluent
import FluentSQL
import Vapor
import GEOSwift
import SwiftTileMatrix

// definition: {"style_url":"http://localhost:50051/dynamic-styles/rockd-cache.v1.0.satellite.json","min_zoom":0.0,"max_zoom":0.0,"pixel_ratio":2.0,"glyphs_rasterization":1,"geometry":{"type":"Polygon","coordinates":[[[-180.0,-90.0],[180.0,-90.0],[180.0,90.0],[-180.0,90.0],[-180.0,-90.0]]]}}
// description: {"layers":["satellite"],"styleVersion":"1.0","updated":"2025-01-10T05:37:00.000Z","name":"rockd-cache.v1.0.satellite","created":"2025-01-10T05:37:00.000Z"}

struct MBXCacheRegionDefinition: Content {
  /** Cache region definition for a Mapbox Maps SDK cache */
  let styleURL: String
  let minZoom: Double
  let maxZoom: Double
  let pixelRatio: Double
  let glyphsRasterization: Int
  let geometry: PolygonGeometry

  struct PolygonGeometry: Content {
    let type: String
    let coordinates: [[[Double]]]
  }

  enum CodingKeys: String, CodingKey {
    case styleURL = "style_url"
    case minZoom = "min_zoom"
    case maxZoom = "max_zoom"
    case pixelRatio = "pixel_ratio"
    case glyphsRasterization = "glyphs_rasterization"
    case geometry
  }
}

struct MBXCacheRegionDescription: Content {
  let layers: [String]
  let styleVersion: String
  let updated: String
  let name: String
  let created: String
}

struct CachedAssetsInfo: Content {
  let resourceSize: Int
  let tileSize: Int
  let resourceCount: Int
  let tileCount: Int
  
  enum CodingKeys : String, CodingKey {
    case resourceSize = "resource_size"
    case tileSize = "tile_size"
    case resourceCount = "resource_count"
    case tileCount = "tile_count"
  }
}

struct MBXCacheRegion: Content {
  let id: Int?
  let definition: MBXCacheRegionDefinition
  let description: MBXCacheRegionDescription
  let cachedAssets: CachedAssetsInfo?
  
  var isGlobal: Bool {
    let tileCoord = TileCoord(0, 0, 0)
    do {
      let geom = try self.asRegionDefinition().geometry
      let area = try geom.area()
      
      let tmsEnvelope = tileCoord.envelope
      let tmsEnvelope4326 = try MultiPoint(
        points: [tmsEnvelope.minXMinY, tmsEnvelope.maxXMaxY]
          .map(webMercatorToEpsg4236)
      ).envelope()
      let tmsArea = try tmsEnvelope4326.area()
      
      print(self.description.name, area, tmsArea)
      
      if area > tmsArea * 0.999 && area < tmsArea * 1.25 {
        return true
      }
      return false
    } catch {
      return false
    }
  }
  
  func asRegionDefinition() throws -> CacheRegionDefinition {
    return CacheRegionDefinition(
      style: .styleURL(definition.styleURL),
      minZoom: Int(definition.minZoom),
      maxZoom: Int(definition.maxZoom),
      pixelRatio: Int(definition.pixelRatio),
      glyphsRasterization: definition.glyphsRasterization,
      geometry: Polygon(exterior: try Polygon.LinearRing(points: definition.geometry.coordinates[0].map { Point(x: $0[0], y: $0[1]) }))
    )
  }
  
  enum CodingKeys: String, CodingKey {
    case id
    case definition
    case description
    case isGlobal = "global"
    case cachedAssets = "assets"
  }
  
  init(
    id: Int? = nil,
    definition: MBXCacheRegionDefinition,
    description: MBXCacheRegionDescription,
    cachedAssets: CachedAssetsInfo? = nil
  ) {
    self.id = id
    self.definition = definition
    self.description = description
    self.cachedAssets = cachedAssets
  }
  
  // Allow encoding of isGlobal as a computed property, but ignore it if sent
  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(id, forKey: .id)
    try container.encode(definition, forKey: .definition)
    try container.encode(description, forKey: .description)
    try container.encode(isGlobal, forKey: .isGlobal)
    try container.encode(cachedAssets, forKey: .cachedAssets)
  }
  
  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = try container.decodeIfPresent(Int.self, forKey: .id)
    self.definition = try container.decode(MBXCacheRegionDefinition.self, forKey: .definition)
    self.description = try container.decode(MBXCacheRegionDescription.self, forKey: .description)
    
    // First try decoding a nested "assets" field, and then try decoding
    // the cached asset keys directly from this object (this handles database row decoding)
    self.cachedAssets = try container.decodeIfPresent(CachedAssetsInfo.self, forKey: .cachedAssets)
      ?? (try? decoder.singleValueContainer().decode(CachedAssetsInfo.self))
  }
  
}

struct CacheRegionsInfo: Content {
  let regions: [MBXCacheRegion]
  let assets: CachedAssetsInfo
}

struct CacheRegionsController: RouteCollection {

  let connectionManager = WebSocketConnectionManager()

  func boot(routes: any RoutesBuilder) throws {
    let regions = routes.grouped("regions")

    regions.get(use: self.index)
    regions.post(use: self.create)
    regions.delete(":id", use: self.deleteCacheRegion)
    regions.webSocket("events", onUpgrade: self.webSocket)
  }
  
  @Sendable
  func index(req: Request) async throws -> CacheRegionsInfo {
    // Get a list of regions
    let sql: SQLQueryString = """
      WITH resources_count AS (
        SELECT
          region_id,
          sum(length(r.data)) resource_size,
          count(r.data) resource_count
        FROM region_resources rr
        JOIN resources r
          ON rr.resource_id = r.id
        GROUP BY rr.region_id
      ), tiles_count AS (
        SELECT
          region_id,
          sum(length(t.data)) tile_size,
          count(t.data) tile_count
        FROM region_tiles rt
        JOIN tiles t
          ON rt.tile_id = t.id
        GROUP BY rt.region_id
      )
      SELECT
        r.id,
        r.definition,
        r.description,
        rc.resource_size,
        rc.resource_count,
        tc.tile_size,
        tc.tile_count
      FROM regions r
      LEFT JOIN resources_count rc
        ON rc.region_id = r.id
      LEFT JOIN tiles_count tc
        ON tc.region_id = r.id
      """

    guard let db = req.db as? any SQLDatabase else {
      throw Abort(.internalServerError, reason: "Database is not SQLDatabase")
    }

    // Description is a JSON string
    let regions = try await db.raw(sql)
      .all(decoding: MBXCacheRegion.self)
    
    let total = try await getTotalSize(db: db)

    return CacheRegionsInfo(regions: regions, assets: total)
  }

  // Route to create a cache region
  @Sendable
  func create(req: Request) async throws -> MBXCacheRegion {
    let regionCandidate = try req.content.decode(MBXCacheRegion.self)

    // Save the region to the database
    guard let db = req.db as? any SQLDatabase else {
      throw Abort(.internalServerError, reason: "Database is not SQLDatabase")
    }
    
    let region = try await createRegion(db, region: regionCandidate)

    // Start the download process (will run outside of the request lifecycle)
    Task.detached {
      do {
        try await self.downloadRegionAssets(region, req: req)
      } catch {
        req.logger.error("Failed to download assets for region: \(error)")
      }
    }

    return region
  }
  
  func downloadRegionAssets(_ region: MBXCacheRegion, req: Request) async throws {
    // This function would handle the downloading of assets for the region
    // You can implement the logic to download tiles, styles, etc. based on the region definition
    // For now, we will just log the region definition
    req.logger.info("Downloading assets for region: \(region.definition)")
    
    let regionDefinition = try region.asRegionDefinition()
    
    
    // Example: You might want to call a service that handles tile downloads
    // await TileDownloadService.downloadTiles(for: region.definition)
  }

  func webSocket(request: Request, ws: WebSocket) {
    // Add the new WebSocket connection to your connection manager
    Task {
      await self.connectionManager.add(ws)
      request.logger.info("WebSocket connected")
    }
    
    ws.onClose.whenComplete { result in
      Task {
        await self.connectionManager.remove(ws)
      }
      switch result {
      case .success:
        request.logger.info("WebSocket closed")
      case .failure(let error):
        request.logger.info("WebSocket closed with error: \(error)")
      }
    }
  }
  
  func deleteCacheRegion(req: Request) async throws -> HTTPStatus {
    guard let id = req.parameters.get("id", as: Int.self) else {
      throw Abort(.badRequest, reason: "Missing region ID")
    }

    // Delete the region from the database
    guard let db = req.db as? any SQLDatabase else {
      throw Abort(.internalServerError, reason: "Database is not SQLDatabase")
    }
    
    try await db.raw(
      "DELETE FROM regions_resources WHERE region_id = \(bind: id)"
    ).run()
    try await db.raw(
      "DELETE FROM regions_tiles WHERE region_id = \(bind: id)"
    ).run()
    try await db.raw(
      "DELETE FROM regions WHERE id = \(bind: id)"
    ).run()

    try await deleteUnreferencedAssets(db: db, log: req.logger)
    return .noContent
  }  
}

func createRegion(_ db: any SQLDatabase, region: MBXCacheRegion) async throws -> MBXCacheRegion {
  let region = try await db.raw(
    "INSERT INTO regions (definition, description) VALUES (\(bind: region.definition), \(bind: region.description)) RETURNING id, definition, description"
  ).first(decoding: MBXCacheRegion.self)
  
  guard let region else {
    throw RuntimeError.databaseError("Failed to create region")
  }
  
  return region
}

struct DeletedAsset: Content {
  let id: Int
  let size: Int
}

func deleteUnreferencedAssets(db: any SQLDatabase, log: Logger) async throws {
  // This function would handle the cleanup of unreferenced assets
  // You can implement the logic to find and delete assets that are no longer referenced by any region
  let sql: SQLQueryString = """
    DELETE FROM resources WHERE id NOT IN (
      SELECT resource_id FROM region_resources
    )
    RETURNING id, length(data) size
  """
  let deletedResources = try await db.raw(sql)
    .all(decoding: DeletedAsset.self)
  
  let deletedTiles = try await db.raw(
    """
    DELETE FROM tiles WHERE id NOT IN (
      SELECT tile_id FROM region_tiles
    )
    RETURNING id, length(data) size
    """
  ).all(decoding: DeletedAsset.self)
  
  let deletedAssets = deletedResources + deletedTiles
  
  let totalSize = deletedAssets.reduce(0) { $0 + $1.size }
  let totalCount = deletedAssets.count
  
  log.info("Deleted \(totalCount) unreferenced assets, total size: \(totalSize) bytes")
}

// You might define a class or actor to manage WebSocket connections
actor WebSocketConnectionManager {
  private var connections: [WebSocket] = []

  func add(_ ws: WebSocket) {
    connections.append(ws)
  }

  func remove(_ ws: WebSocket) {
    connections.removeAll(where: { $0 === ws })
  }

  func sendToAll(_ message: String) async throws {
    for ws in connections {
      try await ws.send(message)
    }
  }
}


func getTotalSize(db: any SQLDatabase) async throws -> CachedAssetsInfo {
  let sql: SQLQueryString = """
      WITH resources_count AS (
        SELECT
          sum(length(data)) resource_size,
          count(data) resource_count
        FROM resources
      ), tiles_count AS (
        SELECT
          sum(length(data)) tile_size,
          count(data) tile_count
        FROM tiles
      )
      SELECT
        rc.resource_size,
        rc.resource_count,
        tc.tile_size,
        tc.tile_count
      FROM resources_count rc, tiles_count tc;
    """
  
  guard let res = try await db.raw(sql).first(decoding: CachedAssetsInfo.self) else {
    throw RuntimeError.databaseError("Could not find cache assets info")
  }
  return res

}
