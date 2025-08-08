//
//  MobileMapCacheDownloadTests.swift
//  MobileMapCache
//
//  Created by Daven Quinn on 8/8/25.
//

import Fluent
import FluentSQLiteDriver
import GEOSwift
import Testing
import VaporTesting
import SwiftTileMatrix
import Numerics

@testable import MobileMapCache



@Suite("Test of cache downloading", .serialized)
struct MobileMapCacheDownloadTests {
  @Test("Find existing tiles and resources to match new potential ones")
  func loadExistingCacheDatabase() async throws {
    try await withExistingDatabase  { app in
      // Load the existing cache database
      let db = app.db as! any SQLDatabase
      
      // Check if the regions table exists
      let tables = try await db.raw("SELECT name FROM sqlite_master WHERE type='table'").all(decodingColumn: "name", as: String.self)
      #expect(tables.contains("regions"), "The 'regions' table should exist in the database")
      
      // There should be 18 tiles in the database
      // Each tileset has 4 or 5 tiles (zooms 0-1)
      // Raster tilesets (terrain RGB and satellite) for some reason don't have zoom 0 tiles
      
      let tileCount = try await db.raw("SELECT count(*) AS count FROM tiles").first(decodingColumn: "count", as: Int.self)
      
      #expect(tileCount == 18, "There should be 18 tiles in the database")
    }
  }
  
  
  @Test("Ensure that no tiles need to be downloaded for existing cache definition")
  func findAllAssetsForRegion() async throws {
    try await withExistingDatabase { app in
      guard let styleURL = Bundle.module.url(forResource: "satellite-style", withExtension: "json") else {
        throw RuntimeError.invalidArgument("Style excerpt not found")
      }
      
      let styleData = try String(contentsOf: styleURL, encoding: .utf8)
      let ext = try Polygon.LinearRing(points: [
        Point(x: -180.0, y: -90.0),
        Point(x: 180.0, y: -90.0),
        Point(x: 180.0, y: 90.0),
        Point(x: -180.0, y: 90.0),
        Point(x: -180.0, y: -90.0)
      ])
      let world = Polygon(exterior: ext)
      
      let def = CacheRegionDefinition(style: .jsonData(styleData), minZoom: 0, maxZoom: 1, pixelRatio: 2, glyphsRasterization: 1, geometry: world)
      
      let regionInfo = try await getRegionAssets(with: app, using: def)
      
      #expect(regionInfo.tiles.tilesAlreadyDownloaded.count == 13, "There should be 18 tiles already downloaded for the region")
      #expect(regionInfo.tiles.tilesToDownload.isEmpty, "There should be no tiles to download for the region")
      #expect(Double(regionInfo.tiles.totalSizeOfTilesDownloaded) > 3e5, "Total size of tiles should be greater than 300 kb")
      
      #expect(regionInfo.resources.resourcesAlreadyDownloaded.count == 13, "There should be 15 resources already downloaded for the region")
      #expect(regionInfo.resources.resourcesToDownload.isEmpty, "There should be no resources to download for the region")
      #expect(Double(regionInfo.resources.totalSizeOfResourcesDownloaded) > 4e5, "Total size of resources should be greater than 400 kb")
      
      
    }
  }
}
