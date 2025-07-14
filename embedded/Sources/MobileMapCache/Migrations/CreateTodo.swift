import Fluent
import FluentSQL
import FluentSQLiteDriver
import Foundation

struct CreateTodo: AsyncMigration {
  func prepare(on database: any Database) async throws {
    try await database.schema("todos")
      .id()
      .field("title", .string, .required)
      .create()
  }

  func revert(on database: any Database) async throws {
    try await database.schema("todos").delete()
  }
}

struct CreateDatabaseSchema: AsyncMigration {
  func prepare(on database: any Database) async throws {
    guard let sqlDatabase = database as? any SQLDatabase else {
      throw RuntimeError.databaseError("Database is not an SQL database")
    }

    // Check if tables already exist, if so, skip migration
    let tablesToCheck = ["regions", "resources", "tiles", "region_resources"]

    let allTables = try await sqlDatabase.raw("SELECT name FROM sqlite_master WHERE type='table'").all(decoding: String.self)

    let existingTables = allTables.filter { tablesToCheck.contains($0) }

    if existingTables.count == tablesToCheck.count {
      // All tables already exist, skip migration
      return
    } else if existingTables.count > 0 {
      let tbl = existingTables.joined(separator: ", ")
      throw RuntimeError.databaseError("Some tables already exist (\(tbl)) but the database is incompletely defined")
    }

    // Get the file path relative to the current file
    let currentFilePath = #file
    // Resolve the absolute path
    let schemaFile = "../../Schema/database-schema.sql"
    let schemaFilePath = URL(fileURLWithPath: currentFilePath)
      .deletingLastPathComponent()
      .appendingPathComponent(schemaFile).path

    let schemaSQL = try String(contentsOfFile: schemaFilePath)
    try await sqlDatabase.raw(SQLQueryString(schemaSQL)).run()
  }

  func revert(on database: any Database) async throws {
    guard let sqlDatabase = database as? any SQLDatabase else {
      throw RuntimeError.databaseError("Database is not an SQL database")
    }
    let dropSQL = """
      DROP TABLE IF EXISTS region_tiles;
      DROP TABLE IF EXISTS tiles;
      DROP TABLE IF EXISTS region_resources;
      DROP TABLE IF EXISTS resources;
      DROP TABLE IF EXISTS regions;
      """
    try await sqlDatabase.raw(SQLQueryString(dropSQL)).run()
  }
}
