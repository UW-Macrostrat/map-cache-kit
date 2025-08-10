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
  var env = try Environment.detect()

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

func withApp(_ test: (Application) async throws -> Void) async throws {
  // Use an in-memory SQLite database for testing
  let cacheDatabase = SQLiteConfiguration(storage: .memory)
  try await withApp(cacheDatabase: cacheDatabase, test)
}

func withExistingDatabase(_ test: (Application) async throws -> Void) async throws {
  // Get fixture
  guard let fixtureURL = Bundle.module.url(forResource: "Rockd-map-cache-v1", withExtension: "db") else {
    throw RuntimeError.invalidArgument("Fixture database not found")
  }
  
  // Copy the test fixture to a temporary path
  // random file name to avoid conflicts
  let fixtureName = UUID().uuidString + ".db"
  let tempDirectory = FileManager.default.temporaryDirectory
  let fixturePath = tempDirectory.appendingPathComponent(fixtureName)
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

@Suite("Tests with existing cache database", .serialized)
struct MobileMapCacheTests {
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
  
  @Test("Find existing tiles in database")
  func findExistingTiles() async throws {
    try await withExistingDatabase { app in
      // Try to download a style and check if the tiles are already in the database
      let sourceURLTemplate = "https://tiles.macrostrat.org/carto/{z}/{x}/{y}.mvt"
      let cacheRegion = try! Polygon(wkt: "POLYGON((-10 -10, -10 10, 10 10, 10 -10, -10 -10))")
      
      let styleJSON = """
      {
          "version": 8,
          "sources": {
              "macrostrat": {
                  "type": "vector",
                  "tiles": [
                      "\(sourceURLTemplate)"
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
        geometry: cacheRegion
      )
      
      let res = try await getTilesToDownload(with: app, using: definition)
      
      #expect(res.tilesToDownload.count == 0)
      #expect(res.tilesAlreadyDownloaded.count == 5)
      // More than a 100 kb of tiles should be downloaded
      #expect(Double(res.totalSizeOfTilesDownloaded) > 1e5)
      
    }
  }
  
  @Test("Find existing tiles for Mapbox style")
  func findExistingTilesForMapboxStyle() async throws {
    try await withExistingDatabase { app in
      // Find existing tiles for a mapbox style that uses tilejson files to define the source
      let cacheRegion = try! Polygon(wkt: "POLYGON((-10 -10, -10 10, 10 10, 10 -10, -10 -10))")
      
      // Get style excerpt
      guard let styleURL = Bundle.module.url(forResource: "satellite-style", withExtension: "json") else {
        throw RuntimeError.invalidArgument("Style excerpt not found")
      }
      // Get JSON as a string
      let styleJSON = try String(contentsOf: styleURL, encoding: .utf8)
      
      let styleDefinition = StyleDefinition.jsonData(styleJSON)
      
      let definition = CacheRegionDefinition(
        style: styleDefinition,
        minZoom: 0,
        maxZoom: 1,
        pixelRatio: 1,
        glyphsRasterization: 1,
        geometry: cacheRegion
      )
      
      let res = try await getTilesToDownload(with: app, using: definition)
      
      #expect(res.tilesToDownload.count == 0)
      #expect(res.tilesAlreadyDownloaded.count == 13)
      // More than a 100 kb of tiles should be downloaded
      #expect(Double(res.totalSizeOfTilesDownloaded) > 1e5)
      
    }
  }
  
  @Test("Find fonts requested by a Mapbox style")
  func findFontsInCacheDatabase() async throws {
    try await withExistingDatabase { app in
      guard let styleURL = Bundle.module.url(forResource: "satellite-style", withExtension: "json") else {
        throw RuntimeError.invalidArgument("Style not found")
      }
      
      let style = try String(contentsOf: styleURL, encoding: .utf8)
      
      // decode the style
      let styleSpec = try JSONDecoder().decode(StyleSpec.self, from: Data(style.utf8))
      
      let fontStacks = findFontsRequestedByMapboxStyle(spec: styleSpec)
      
      var totalSize: Int64 = 0
      
      let fontStackURLs = try getFontStackURLs(styleSpec, fontStacks: Array(fontStacks), ranges: ["0-255"])
      
      for url in fontStackURLs {
        guard let size = try await findResourceInDatabase(db: app.db, url: url, kind: .font) else {
          throw RuntimeError.invalidArgument("Font stack \(url) not found in database")
        }
        
        totalSize += size
        
      }
      
      #expect(fontStacks.count == 6, "There should be at least one font stack in the style")
      #expect(Double(totalSize) > 1e5, "Total size of fonts should be greater than 0")
    }
  }
  
  
  @Test("Find all resources requested by mapbox style")
  func findAllResourcesRequestedByMapboxStyle() async throws {
    try await withExistingDatabase { app in
      guard let styleURL = Bundle.module.url(forResource: "satellite-style", withExtension: "json") else {
        throw RuntimeError.invalidArgument("Style excerpt not found")
      }
      
      let style = try String(contentsOf: styleURL, encoding: .utf8)
      
      // decode the style
      let styleSpec = try JSONDecoder().decode(StyleSpec.self, from: Data(style.utf8))
      
      let resources = try findResourcesRequestedByMapboxStyle(spec: styleSpec, options: ResourceFindOptions(maxCodePoint: 255))
      
      #expect(resources.count > 10, "There should be at least ten resources requested by the style")
      
      let fontStacks = resources.filter { $0.kind == .font }
      #expect(fontStacks.count == 6, "There should be six font stacks in the style")
      let spriteResources = resources.filter { $0.kind == .sprite || $0.kind == .spritejson }
      #expect(spriteResources.count == 4, "There should be four sprite resources in the style")
      let sourceResources = resources.filter { $0.kind == .source }
      #expect(sourceResources.count == 3, "There should be three source resources in the style")
  
      var totalSize: Int64 = 0
      for resource in resources {
        guard let size = try await findResourceInDatabase(db: app.db, url: resource.urlTemplate, kind: resource.kind) else {
          throw RuntimeError.invalidArgument("Resource \(resource.urlTemplate) not found in database")
        }
        
        totalSize += size
        
      }
      
      #expect(Double(totalSize) > 4e5, "Total size of resources should be greater than 400 kb")
    }
  }
}

@Test("Find fonts requested by a Mapbox style")
func findFontsRequestedByMapboxStyle() async throws {
  guard let styleURL = Bundle.module.url(forResource: "satellite-style", withExtension: "json") else {
    throw RuntimeError.invalidArgument("Style excerpt not found")
  }
  
  let style = try String(contentsOf: styleURL, encoding: .utf8)
  
  // decode the style
  let styleSpec = try JSONDecoder().decode(StyleSpec.self, from: Data(style.utf8))

  let fontStacks = findFontsRequestedByMapboxStyle(spec: styleSpec)
  
  #expect(fontStacks.count == 6, "There should be at least one font stack in the style")
  
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
      let defs = try await getCacheableTileLayersFromStyle(with: app, style: styleDefinition)
      
      #expect(defs.count == 1)
      #expect(defs.first?.urlTemplate == "https://example.com/tiles/{z}/{x}/{y}.pbf")
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

@Test("Canonicalize Mapbox style URL for caching")
func canonicalizeStyleURLForCaching() async throws {
  let styleURL = "https://api.mapbox.com/styles/v1/mapbox/streets-v11"
  let canonicalizedURL = getMapboxCanonicalURL(styleURL)
  #expect(
    canonicalizedURL.templateURL == "mapbox://styles/mapbox/streets-v11"
  )
}

@Test("Get style URL for request")
func getStyleURLForRequest() async throws {
  let canonicalURL = "mapbox://tiles/mapbox.mapbox-streets-v8/{z}/{x}/{y}.vector.pbf"
}

@Test("Download tile that has no data")
func downloadNoDataTile() async throws {
  let urlTemplate = "mapbox://tiles/mapbox.mapbox-streets-v8/{z}/{x}/{y}.vector.pbf"
  let tile = CandidateTile(x: 8, y: 15, z: 4, urlTemplate: urlTemplate)
  
}
