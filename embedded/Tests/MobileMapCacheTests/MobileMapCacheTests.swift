import Fluent
import GEOSwift
import Testing
import VaporTesting

@testable import MobileMapCache

@Suite("App Tests with DB", .serialized)
struct MobileMapCacheTests {
  private func withApp(_ test: (Application) async throws -> Void) async throws {
    let app = try await Application.make(.testing)
    do {
      try await configure(app)
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

  @Test("Test Hello World Route")
  func helloWorld() async throws {
    try await withApp { app in
      try await app.testing().test(
        .GET, "hello",
        afterResponse: { res async in
          #expect(res.status == .ok)
          #expect(res.body.string == "Hello, world!")
        })
    }
  }

  @Test("Getting all the Todos")
  func getAllTodos() async throws {
    try await withApp { app in
      let sampleTodos = [Todo(title: "sample1"), Todo(title: "sample2")]
      try await sampleTodos.create(on: app.db)

      try await app.testing().test(
        .GET, "todos",
        afterResponse: { res async throws in
          #expect(res.status == .ok)
          #expect(try res.content.decode([TodoDTO].self) == sampleTodos.map { $0.toDTO() })
        })
    }
  }

  @Test("Creating a Todo")
  func createTodo() async throws {
    let newDTO = TodoDTO(id: nil, title: "test")

    try await withApp { app in
      try await app.testing().test(
        .POST, "todos",
        beforeRequest: { req in
          try req.content.encode(newDTO)
        },
        afterResponse: { res async throws in
          #expect(res.status == .ok)
          let models = try await Todo.query(on: app.db).all()
          #expect(models.map({ $0.toDTO().title }) == [newDTO.title])
        })
    }
  }

  @Test("Deleting a Todo")
  func deleteTodo() async throws {
    let testTodos = [Todo(title: "test1"), Todo(title: "test2")]

    try await withApp { app in
      try await testTodos.create(on: app.db)

      try await app.testing().test(
        .DELETE, "todos/\(testTodos[0].requireID())",
        afterResponse: { res async throws in
          #expect(res.status == .noContent)
          let model = try await Todo.find(testTodos[0].id, on: app.db)
          #expect(model == nil)
        })
    }
  }
}

extension TodoDTO: Equatable {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.id == rhs.id && lhs.title == rhs.title
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
