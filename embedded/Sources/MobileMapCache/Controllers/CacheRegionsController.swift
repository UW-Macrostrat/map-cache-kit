//
//  CacheRegionsController.swift
//  MobileMapCache
//
//  Created by Daven Quinn on 5/17/25.
//

import Fluent
import Vapor
import FluentSQL

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

struct MBXCacheRegion: Content {
  let id: Int
  let definition: MBXCacheRegionDefinition
  let description: MBXCacheRegionDescription
}


struct CacheRegionsController: RouteCollection {
  func boot(routes: any RoutesBuilder) throws {
    let regions = routes.grouped("regions")
    
    regions.get(use: self.index)
  }
  
  @Sendable
  func index(req: Request) async throws -> [MBXCacheRegion] {
    // Get a list of regions
    let sql: SQLQueryString = """
      SELECT id, definition, description FROM regions
      """
    
    guard let db = req.db as? any SQLDatabase else {
      throw Abort(.internalServerError, reason: "Database is not SQLDatabase")
    }
    
    // Description is a JSON string
    let regions = try await db.raw(sql)
      .all(decoding: MBXCacheRegion.self)
    
    return regions
  }
}
