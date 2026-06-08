import Fluent
import FluentSQL
import FluentSQLiteDriver
import Foundation

struct CreateDatabaseSchemaMigration: AsyncMigration {
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
    } else if existingTables.count > 0 {
      let tbl = existingTables.joined(separator: ", ")
      throw RuntimeError.databaseError("Some tables already exist (\(tbl)) but the database is incompletely defined")
    } else {
      // Split queries by semicolon and remove empty lines
      try await runSQL(sqlDatabase, statements: databaseSchemaSQL)
    }
  }

  func revert(on database: any Database) async throws {
    guard let sqlDatabase = database as? any SQLDatabase else {
      throw RuntimeError.databaseError("Database is not an SQL database")
    }
    // language=SQL
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

// language=SQL
let databaseSchemaSQL = """
  CREATE TABLE regions (
    id INTEGER NOT NULL primary key autoincrement,
    definition TEXT NOT NULL,
    description BLOB,
    style TEXT,
    required_resource_count INTEGER
  );

  CREATE UNIQUE INDEX unique_style_url on regions (style);

  CREATE TABLE resources (
    id INTEGER NOT NULL primary key autoincrement,
    url TEXT NOT NULL unique,
    kind INTEGER NOT NULL,
    expires INTEGER,
    modified INTEGER,
    etag TEXT,
    data BLOB,
    compressed INTEGER default 0 NOT NULL,
    accessed INTEGER NOT NULL,
    must_revalidate INTEGER default 0 NOT NULL
  );

  CREATE TABLE region_resources (
    region_id INTEGER NOT NULL references regions on delete cascade,
    resource_id INTEGER NOT NULL references resources,
    UNIQUE (region_id, resource_id)
  );

  CREATE INDEX region_resources_resource_id on region_resources (resource_id);

  CREATE INDEX resources_accessed on resources (accessed);

  CREATE INDEX resources_url on resources (url);

  CREATE TABLE tiles (
    id INTEGER NOT NULL primary key autoincrement,
    url_template TEXT NOT NULL,
    pixel_ratio INTEGER NOT NULL,
    z INTEGER NOT NULL,
    x INTEGER NOT NULL,
    y INTEGER NOT NULL,
    expires INTEGER,
    modified INTEGER,
    etag TEXT,
    data BLOB,
    compressed INTEGER default 0 NOT NULL,
    accessed INTEGER NOT NULL,
    must_revalidate INTEGER default 0 NOT NULL,
    UNIQUE (url_template, pixel_ratio, z, x, y)
  );

  CREATE TABLE region_tiles (
    region_id INTEGER NOT NULL references regions on delete cascade,
    tile_id INTEGER NOT NULL references tiles,
    UNIQUE (region_id, tile_id)
  );
"""

struct CreateIndicesMigration: AsyncMigration {
  /** Create the basic database schema conforming to the original cache system. */
  func prepare(on database: any Database) async throws {
    guard let sqlDatabase = database as? any SQLDatabase else {
      throw RuntimeError.databaseError("Database is not an SQL database")
    }
    // language=SQL
    let buildIndicesSQL = """
      CREATE INDEX IF NOT EXISTS region_tiles_tile_id on region_tiles (tile_id);
      CREATE INDEX IF NOT EXISTS tiles_accessed on tiles (accessed);
      CREATE INDEX IF NOT EXISTS tiles_url_template on tiles (url_template);
      CREATE INDEX IF NOT EXISTS tiles_spatial_index ON tiles (url_template, x, y, z);
    """
    
    // Build indices
    try await runSQL(sqlDatabase, statements: buildIndicesSQL)
  }
  
  func revert(on database: any Database) async throws {
    guard let sqlDatabase = database as? any SQLDatabase else {
      throw RuntimeError.databaseError("Database is not an SQL database")
    }
    // language=SQL
    let dropSQL = """
      DROP INDEX IF EXISTS region_tiles_tile_id;
      DROP INDEX IF EXISTS tiles_accessed;
      DROP INDEX IF EXISTS tiles_url_template;
      DROP INDEX IF EXISTS tiles_spatial_index;
      """
    try await runSQL(sqlDatabase, statements: dropSQL)
  }
}

struct CreateSizeColumnsMigration: AsyncMigration {
  /** Create the basic database schema conforming to the original cache system. */
  func prepare(on database: any Database) async throws {
    guard let sqlDatabase = database as? any SQLDatabase else {
      throw RuntimeError.databaseError("Database is not an SQL database")
    }
    
    for table in ["resources", "tiles"] {
      if try await sqlDatabase.raw("SELECT 1 FROM pragma_table_info(\(bind: table)) WHERE name = 'data_size'").first() != nil {
        // Column already exists, skip
        continue
      }

      // If the query fails, we assume the column doesn't exist and proceed with migration
      // language=SQL
      try await runSQL(sqlDatabase, statements: "ALTER TABLE \(table) ADD COLUMN data_size INTEGER NOT NULL DEFAULT 0")
      try await runSQL(sqlDatabase, statements: "UPDATE \(table) SET data_size = coalesce(length(data), 0)")
    }
  }
  
  func revert(on database: any Database) async throws {
    guard let sqlDatabase = database as? any SQLDatabase else {
      throw RuntimeError.databaseError("Database is not an SQL database")
    }
    // language=SQL
    try await runSQL(sqlDatabase, statements: """
      DROP COLUMN IF EXISTS data_size FROM tiles;
      DROP COLUMN IF EXISTS data_size FROM resources;
      """)
  }
}

func indexExists(_ database: any SQLDatabase, indexName: String) async throws -> Bool {
  let result = try await database.raw("SELECT name FROM sqlite_master WHERE type='index' AND name = \(bind: indexName)").first(decodingColumn: "name", as: String.self)
  return result != nil
}

func runSQL(_ database: any SQLDatabase, statements: String) async throws {
  // Run raw SQL statements
  let queries = statements.split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
  for query in queries {
    try await database.raw(SQLQueryString(query)).run()
  }
}
