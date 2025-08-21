//
//  MapCacheKitDownloadTests.swift
//  MapCacheKit
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

@testable import MapCacheKit

func worldPolygon() throws -> Polygon {
  let ext = try Polygon.LinearRing(points: [
    Point(x: -180.0, y: -90.0),
    Point(x: 180.0, y: -90.0),
    Point(x: 180.0, y: 90.0),
    Point(x: -180.0, y: 90.0),
    Point(x: -180.0, y: -90.0)
  ])
  return Polygon(exterior: ext)
}

@Suite("Test of cache downloading", .serialized)
struct MapCacheKitDownloadTests {
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
      let satelliteStyle = try getSatelliteStyle()
      let def = CacheRegionDefinition(
        styles: [satelliteStyle],
        minZoom: 0,
        maxZoom: 1,
        pixelRatio: 2,
        glyphsRasterization: 1,
        geometry: try worldPolygon(),
      )

      let regionInfo = try await getRegionAssets(
        with: app,
        using: def,
        options: ResourceFindOptions(maxCodePoint: 255)
      )

      #expect(regionInfo.tiles.alreadyDownloaded.count == 13, "There should be 18 tiles already downloaded for the region")
      #expect(regionInfo.tiles.toDownload.isEmpty, "There should be no tiles to download for the region")
      #expect(Double(regionInfo.tiles.totalSizeDownloaded) > 3e5, "Total size of tiles should be greater than 300 kb")

      #expect(regionInfo.resources.alreadyDownloaded.count == 13, "There should be 15 resources already downloaded for the region")
      #expect(regionInfo.resources.toDownload.isEmpty, "There should be no resources to download for the region")
      #expect(Double(regionInfo.resources.totalSizeDownloaded) > 4e5, "Total size of resources should be greater than 400 kb")
    }
  }

  @Test("Expect that tiles need to be downloaded for a new cache area (more local)")
  func findAssetsForNewRegion() async throws {
    try await withExistingDatabase { app in
      let styleData = try getSatelliteStyle()

      let topLeft = Point(x: -10.0, y: 50.0)
      let bottomRight = Point(x: 10.0, y: 40.0)

      let newRegion = Envelope(minX: -10.0, maxX: 10.0, minY: 40.0, maxY: 50.0).geometry

      guard case .polygon(let polygon) = newRegion else {
        throw RuntimeError.invalidArgument("New region is not a polygon")
      }

      // Create a new region definition that is smaller than the existing one
      let def = CacheRegionDefinition(styles: [styleData], minZoom: 0, maxZoom: 2, pixelRatio: 2, glyphsRasterization: 1, geometry: polygon)

      // Get the assets for the new region
      let regionInfo = try await getRegionAssets(with: app, using: def, options: ResourceFindOptions(maxCodePoint: 255))

      #expect(regionInfo.tiles.alreadyDownloaded.count == 7, "There should be 13 tiles already downloaded for the region")
      #expect(regionInfo.tiles.toDownload.count == 6, "There should be 5 tiles to download for the region")
      #expect(Double(regionInfo.tiles.totalSizeDownloaded) > 2e5, "Total size of tiles should be greater than 300 kb")

      #expect(regionInfo.resources.alreadyDownloaded.count == 13, "There should be 13 resources already downloaded for the region")
      #expect(regionInfo.resources.toDownload.isEmpty, "There should be no resources to download for the region")
    }
  }
}


@Test("Download new tiles for cache region")
func downloadNewTilesForCacheRegion() async throws {
  try await withApp { app in
    guard let styleURL = Bundle.module.url(forResource: "satellite-style", withExtension: "json") else {
      throw RuntimeError.invalidArgument("Style excerpt not found")
    }

    let styleData = try JSONDecoder().decode(JSON.self, from: Data(contentsOf: styleURL))

    let def = CacheRegionDefinition(
      styles: [.jsonData(styleData)],
      minZoom: 0,
      maxZoom: 1,
      pixelRatio: 2,
      glyphsRasterization: 1,
      geometry: try worldPolygon()
    )

    let regionInfo = try await getRegionAssets(with: app, using: def, options: ResourceFindOptions(maxCodePoint: 255))

    #expect(regionInfo.tiles.alreadyDownloaded.isEmpty, "There should be no tiles already downloaded for the region")
    #expect(regionInfo.tiles.toDownload.count == 13, "There should be 13 tiles to download for the region")

    #expect(regionInfo.resources.alreadyDownloaded.isEmpty, "There should be no resources already downloaded for the region")
    #expect(regionInfo.resources.toDownload.count == 13, "There should be 13 resources to download for the region")
    #expect(Double(regionInfo.resources.totalSizeDownloaded) == 0, "Total size of resources should be greater than 400 kb")

    guard let db = app.db as? any SQLDatabase else {
      throw RuntimeError.invalidArgument("Database is not SQLDatabase")
    }

    // Check that the database is empty
    let tileCount = try await db.raw("SELECT count(*) AS count FROM tiles").first(decodingColumn: "count", as: Int.self)
    #expect(tileCount == 0, "There should be no tiles in the database before download")

    let regionCount = try await db.raw("SELECT count(*) AS count FROM regions").first(decodingColumn: "count", as: Int.self)
    #expect(regionCount == 0, "There should be no regions in the database before download")

    let resourceCount = try await db.raw("SELECT count(*) AS count FROM resources").first(decodingColumn: "count", as: Int.self)
    #expect(resourceCount == 0, "There should be no resources in the database before download")

    let legacyDef = MBXCacheRegionDefinition(
      styleURL: "http://localhost:50051/dynamic-styles/rockd-cache.v1.0.satellite.json",
      minZoom: 0,
      maxZoom: 1,
      pixelRatio: 2.0,
      glyphsRasterization: 1,
      geometry: PolygonGeometry(
        type: "Polygon",
        coordinates: [[[-180.0, -90.0], [180.0, -90.0], [180.0, 90.0], [-180.0, 90.0], [-180.0, -90.0]]]
      )
    )

    let legacyRegion = MBXCacheRegion(
      id: nil,
      definition: legacyDef,
      description: MBXCacheRegionDescription(
        layers: ["satellite"],
        styleVersion: "1.0",
        updated: "2025-01-10T05:37:00.000Z",
        name: "rockd-cache.v1.0.satellite",
        created: "2025-01-10T05:37:00.000Z"
      )
    )

    #expect(legacyRegion.isGlobal, "Legacy region should cover the entire world")


    let region = try await createRegion(db, region: legacyRegion)
    guard let regionID = region.id else {
      throw RuntimeError.invalidArgument("Region ID should not be nil")
    }

    #expect(try app.config.mapboxAPIToken != nil, "Mapbox API token should be set in the application config")

    let res1 = try await downloadRegionAssets(
      with: app,
      using: def,
      regionID: regionID,
      options: ResourceFindOptions(maxCodePoint: 255)
    )

    #expect(
      res1.tilesDownloaded == 13,
      "13 tiles should be downloaded for the region"
    )
    #expect(
      res1.tilesFailed == 0,
      "There should be no tiles that failed to download"
    )

    #expect(
      res1.resourcesDownloaded == 13,
      "13 resources should be downloaded for the region"
    )

    #expect(
      res1.resourcesFailed == 0,
      "There should be no resources that failed to download"
    )
  }
}
