import Fluent
import FluentSQL
import FluentSQLiteDriver
import Foundation

struct CreateDatabaseSchema: AsyncMigration {
  /** Create the basic database schema conforming to the original cache system. */
  func prepare(on database: any Database) async throws {
    guard let sqlDatabase = database as? any SQLDatabase else {
      throw RuntimeError.databaseError("Database is not an SQL database")
    }

    // Check if tables already exist, if so, skip migration
    let tablesToCheck = ["regions", "resources", "tiles", "region_resources"]
    
    let allTables = try await sqlDatabase.raw("SELECT name FROM sqlite_master WHERE type='table'").all(decodingColumn: "name", as: String.self)

    let existingTables = allTables.filter { tablesToCheck.contains($0) }

    if existingTables.count == tablesToCheck.count {
      // All tables already exist, skip migration
      return
    } else if existingTables.count > 0 {
      let tbl = existingTables.joined(separator: ", ")
      throw RuntimeError.databaseError("Some tables already exist (\(tbl)) but the database is incompletely defined")
    }

    guard let path = Bundle.module.url(forResource: "Schema/database-schema", withExtension: "sql") else {
      throw RuntimeError.databaseError("Schema file not found")
    }
    
    let schemaSQL = try String(contentsOf: path, encoding: .utf8)
  
    // Split queries by semicolon and remove empty lines
    try await runSQL(sqlDatabase, statements: schemaSQL)
    
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
    try await runSQL(sqlDatabase, statements: dropSQL)
  }
}

func runSQL(_ database: any SQLDatabase, statements: String) async throws {
  // Run raw SQL statements
  let queries = statements.split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
  for query in queries {
    try await database.raw(SQLQueryString(query)).run()
  }
}
