import Fluent
import FluentSQLiteDriver
import GEOSwift
import Testing
import VaporTesting

@testable import MobileMapCache

@Suite("App Tests with DB", .serialized)
struct MobileMapCacheTests {
  private func withApp(_ test: (Application) async throws -> Void) async throws {
    // Use an in-memory SQLite database for testing
    let cacheDatabase = SQLiteConfiguration(storage: .memory)
    try await withApp(cacheDatabase: cacheDatabase, test)
  }

  private func withApp(cacheDatabase: SQLiteConfiguration, _ test: (Application) async throws -> Void) async throws {
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

  // @Test("Test Hello World Route")
  // func helloWorld() async throws {
  //   try await withApp { app in
  //     try await app.testing().test(
  //       .GET, "hello",
  //       afterResponse: { res async in
  //         #expect(res.status == .ok)
  //         #expect(res.body.string == "Hello, world!")
  //       })
  //   }
  // }

  // @Test("Getting all the Todos")
  // func getAllTodos() async throws {
  //   try await withApp { app in
  //     let sampleTodos = [Todo(title: "sample1"), Todo(title: "sample2")]
  //     try await sampleTodos.create(on: app.db)

  //     try await app.testing().test(
  //       .GET, "todos",
  //       afterResponse: { res async throws in
  //         #expect(res.status == .ok)
  //         #expect(try res.content.decode([TodoDTO].self) == sampleTodos.map { $0.toDTO() })
  //       })
  //   }
  // }

  // @Test("Creating a Todo")
  // func createTodo() async throws {
  //   let newDTO = TodoDTO(id: nil, title: "test")

  //   try await withApp { app in
  //     try await app.testing().test(
  //       .POST, "todos",
  //       beforeRequest: { req in
  //         try req.content.encode(newDTO)
  //       },
  //       afterResponse: { res async throws in
  //         #expect(res.status == .ok)
  //         let models = try await Todo.query(on: app.db).all()
  //         #expect(models.map({ $0.toDTO().title }) == [newDTO.title])
  //       })
  //   }
  // }

  // @Test("Deleting a Todo")
  // func deleteTodo() async throws {
  //   let testTodos = [Todo(title: "test1"), Todo(title: "test2")]

  //   try await withApp { app in
  //     try await testTodos.create(on: app.db)

  //     try await app.testing().test(
  //       .DELETE, "todos/\(testTodos[0].requireID())",
  //       afterResponse: { res async throws in
  //         #expect(res.status == .noContent)
  //         let model = try await Todo.find(testTodos[0].id, on: app.db)
  //         #expect(model == nil)
  //       })
  //   }
  // }

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
