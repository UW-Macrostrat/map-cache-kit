import Fluent
import FluentSQLiteDriver
import GEOSwift
import Testing
import VaporTesting
import SwiftTileMatrix
import Numerics

@testable import MobileMapCache

fileprivate func withApp(cacheDatabase: SQLiteConfiguration, _ test: (Application) async throws -> Void) async throws {
  // Set an environment variable for an in-memory database for testing
  
  let app = try await Application.make(.testing)
  do {
    // Configure the app with an in-memory SQLite database
    try await configure(app, cacheDatabase: cacheDatabase)
    try await app.autoMigrate()
    try await test(app)
    try await app.autoRevert()
  } catch {
    try? await app.autoRevert()
    try await app.asyncShutdown()
    throw error
  }
  try await app.asyncShutdown()
}

extension TileCoord: @unchecked Sendable {
  
}

fileprivate func withApp(_ test: (Application) async throws -> Void) async throws {
  // Use an in-memory SQLite database for testing
  let cacheDatabase = SQLiteConfiguration(storage: .memory)
  try await withApp(cacheDatabase: cacheDatabase, test)
}

@Suite("Tests with existing cache database", .serialized)
struct MobileMapCacheTests {
  private func withExistingDatabase(_ test: (Application) async throws -> Void) async throws {
    // Get fixture
    guard let fixtureURL = Bundle.module.url(forResource: "Rockd-map-cache-v1", withExtension: "db") else {
      throw RuntimeError.invalidArgument("Fixture database not found")
    }
    
    // Copy the test fixture to a temporary path
    let tempDirectory = FileManager.default.temporaryDirectory
    let fixturePath = tempDirectory.appendingPathComponent("Rockd-map-cache-v1.db")
    // Delete the file if it exists
    if FileManager.default.fileExists(atPath: fixturePath.path) {
      try FileManager.default.removeItem(at: fixturePath)
    }
    try FileManager.default.copyItem(at: fixtureURL, to: fixturePath)
    
    // Ensure the file exists
    guard FileManager.default.fileExists(atPath: fixturePath.path) else {
      throw RuntimeError.invalidArgument("Fixture database file does not exist at \(fixturePath.path)")
    }
    
    let cacheDatabase = SQLiteConfiguration.file(fixturePath.path)
    
    try await withApp(cacheDatabase: cacheDatabase, test)
  }

  @Test("Load an existing cache database")
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
  
  @Test("Serve a cached tile")
  func serveCachedTile() async throws {
    try await withExistingDatabase { app in
      // Serve a cached tile
      try await app.testing().test(
        .GET, "/tiles/v4/mapbox.terrain-rgb/1/0/0.webp?x-cache-domain=api.mapbox.com&x-cache-mode=cache",
        afterResponse: { res async throws in
          #expect(res.status == .ok)
          #expect(res.headers.contentType == .png)
          #expect(res.body.readableBytes > 0, "The tile should have content")
        })
    }
  }

  @Test("Serve a cached resource")
  func serveCachedResource() async throws {
    try await withExistingDatabase { app in
      // Serve a cached resource
      try await app.testing().test(
        .GET, "/tiles/fonts/v1/jczaplewski/DIN%20Offc%20Pro%20Medium%2cArial%20Unicode%20MS%20Regular/0-255.pbf?x-cache-domain=api.mapbox.com&x-cache-mode=cache",
        afterResponse: { res async throws in
          #expect(res.status == .ok)
          #expect(res.headers["Content-Type"].first == "application/x-protobuf")
          #expect(res.body.readableBytes > 0, "The resource should have content")
        })
    }
  }

}

@Suite("Tests with new cache database")
struct MobileMapCacheNewDatabaseTests {
  
  @Test("Check that the tables are created")
  func checkTablesCreated() async throws {
    // Check that the cache_regions table exists
    try await withApp { app in
      let db = app.db as! any SQLDatabase
      
      let tables = try await db.raw("SELECT name FROM sqlite_master WHERE type='table'").all(decodingColumn: "name", as: String.self)
      
      for table in ["regions", "resources", "tiles", "region_resources"] {
        // Check if the table exists
        #expect(tables.contains(table), "Table \(table) should exist in the database")
      }
    }
  }
  
  @Test("Parsing Tile URL Templates from Style")
  func parseTileURLTemplates() async throws {
    try await withApp { app in
      let styleJSON = """
      {
          "version": 8,
          "sources": {
              "example-source": {
                  "type": "vector",
                  "tiles": [
                      "https://example.com/tiles/{z}/{x}/{y}.pbf"
                  ]
              }
          }
      }
      """
      let styleDefinition = StyleDefinition.jsonData(styleJSON)
      let templates = try await getTileURLTemplatesFromStyle(with: app, style: styleDefinition)
      
      #expect(templates.count == 1)
      #expect(templates.first == "https://example.com/tiles/{z}/{x}/{y}.pbf")
    }
  }
  
  @Test("Downloading Tiles from Style URL")
  func downloadTilesFromStyle() async throws {
    try await withApp { app in
      let styleJSON = """
      {
          "version": 8,
          "sources": {
              "example-source": {
                  "type": "vector",
                  "tiles": [
                      "https://example.com/tiles/{z}/{x}/{y}.pbf"
                  ]
              }
          }
      }
      """
      let styleDefinition = StyleDefinition.jsonData(styleJSON)
      let definition = CacheRegionDefinition(
        style: styleDefinition,
        minZoom: 0,
        maxZoom: 1,
        pixelRatio: 1,
        glyphsRasterization: 1,
        geometry: try! Polygon(wkt: "POLYGON((-1 -1, -1 1, 1 1, 1 -1, -1 -1))")
      )
      
      try await downloadTileCache(with: app, using: definition)
      
      // //let tiles = try await app.db.query("SELECT COUNT(*) AS count FROM tiles").first()
      // guard let tileCount = tiles?["count"]?.int else {
      //   throw RuntimeError.invalidArgument("Failed to fetch tile count from database")
      // }
      
      // #expect(tileCount > 0)
    }
  }
}

struct ParentTileTestCase: Sendable {
  let polygon: Polygon
  let expectedTile: TileCoord
}

let parentTileTestCases = [
  ParentTileTestCase(
    polygon: try! Polygon(wkt: "POLYGON((-1 -1, -1 1, 1 1, 1 -1, -1 -1))"),
    expectedTile: TileCoord(0, 0, 0)
  ),
  ParentTileTestCase(
    polygon: try! Polygon(wkt: "POLYGON((-180 -85.0511, -180 85.0511, 180 85.0511, 180 -85.0511, -180 -85.0511))"),
    expectedTile: TileCoord(0, 0, 0)
  ),
  ParentTileTestCase(polygon: try! Polygon(wkt: "POLYGON((-180 0.1, -0.1 0.1, -0.1 85.0511, -180 85.0511, -180 0.1))"),
                     expectedTile: TileCoord(0, 0, 1))
]

@Suite("Tests for tile intersections", .serialized)
struct IntersectingTileTests {
  @Test("EPSG:4326 to web mercator")
  func testEpsg4326ToWebMercator() {
    // Define a point in EPSG:4326
    let pointWKT = "POINT(-180 0)"
    
    // Convert to Web Mercator
    let point = try! Point(wkt: pointWKT)
    let webMercatorPoint = epsg4326ToWebMercator(point: point)
    
    // Check the coordinates
    #expect(webMercatorPoint.x == -webMercatorGridSize/2.0)
    #expect(webMercatorPoint.y.isApproximatelyEqual(to: 0.0, absoluteTolerance: 1e-7), "Y coordinate should match Web Mercator conversion")
  }
  
  @Test("EPSG:4326 to web mercator 2")
  func testEpsg4326ToWebMercator2() {
    // Define a point in EPSG:4326 at the edge of the grid
    // Convert to Web Mercator
    let point = Point(x: 180, y: 85.051129)
    let webMercatorPoint = epsg4326ToWebMercator(point: point)
    
    // Check the coordinates
    #expect(webMercatorPoint.x == webMercatorGridSize/2.0)
    #expect(webMercatorPoint.y.isApproximatelyEqual(to: webMercatorGridSize/2.0, absoluteTolerance: 1), "Y coordinate should match Web Mercator conversion")
  }
  
  @Test("Get parent tile", arguments: parentTileTestCases)
  func getParentTileOfGeometry(_ arguments: ParentTileTestCase) throws {
    // Define a polygon that intersects with some tiles
    //let polygonWKT = "POLYGON((-180 -85.0511, -180 85.0511, 180 85.0511, 180 -85.0511, -180 -85.0511))"
    //let polygon = try Polygon(wkt: polygonWKT)
    
    // Get the parent tile at zoom level 0
    let parentTile = try getParentTile(for: arguments.polygon.geometry)
    
    // The expected tile at zoom level 0 for this point is (0, 0)
    #expect(parentTile == arguments.expectedTile)
  }
  
  @Test("Get intersecting tiles for polygon")
  func getIntersectingTilesForPolygon() throws {
    
    // Define a polygon that intersects with some tiles
    let polygonWKT = "POLYGON((-1 -1, -1 1, 1 1, 1 -1, -1 -1))"
    let polygon = try Polygon(wkt: polygonWKT)
    
    // Get intersecting tiles
    let intersectingTiles = try getIntersectingTiles(for: polygon.geometry, minZoom: 0, maxZoom: 1)
    
    #expect(intersectingTiles.count == 5)
    
    let intersectingTiles2 = try getIntersectingTiles(for: polygon.geometry, minZoom: 0, maxZoom: 2)
    #expect(intersectingTiles2.count == 9)
  }
  
  @Test("Get intersecting tiles for entire Web Mercator world")
  func getIntersectingTilesForWorld() throws {
    
    // Define a polygon that covers the entire Web Mercator world
    let polygonWKT = "POLYGON((-180 -85.0511, -180 85.0511, 180 85.0511, 180 -85.0511, -180 -85.0511))"
    let polygon = try Polygon(wkt: polygonWKT)
    
    // Get intersecting tiles for the entire world at zoom level 0
    let intersectingTiles = try getIntersectingTiles(for: polygon.geometry, minZoom: 0, maxZoom: 0)
    
    #expect(intersectingTiles.count == 1, "There should be only one tile at zoom level 0 covering the entire world")
    
    let intersectingTiles2 = try getIntersectingTiles(for: polygon.geometry, minZoom: 1, maxZoom: 1)
    #expect(intersectingTiles2.count == 4, "There should be 4 tiles at zoom level 1 covering the entire world")
    
  }
}
