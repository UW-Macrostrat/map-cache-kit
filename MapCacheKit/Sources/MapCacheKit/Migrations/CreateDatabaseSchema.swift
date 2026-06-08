import Fluent
import FluentSQL
import FluentSQLiteDriver
import Foundation

protocol Migration {
  func isApplied(on db: any SQLDatabase) async throws -> Bool
  func shouldApply(on db: any SQLDatabase) async throws -> Bool
  func run(on db: any SQLDatabase) async throws
  var name: String { get }
}

extension Migration {
  func isApplied(on database: any SQLDatabase) async throws -> Bool {
    let shouldApply = try await self.shouldApply(on: database)
    return !shouldApply
  }
  
  // Get the name from the struct name by default
  var name: String {
    String(describing: Self.self)
  }
}

class MigrationSystem {
  private var migrations: [any Migration] = []
  
  init(migrations: [any Migration]) {
    self.migrations = migrations
  }
  
  func run(on database: any SQLDatabase, logger: Logger? = nil) async throws {
    logger?.info("Running database migrations")
    for migration in migrations {
      if try await migration.shouldApply(on: database) {
        logger?.info("Applying migration: \(migration.name)")
        try await migration.run(on: database)
        logger?.info("Successfully applied migration: \(migration.name)")
      } else {
        logger?.info("Skipping migration \(migration.name) as it is already applied")
      }
    }
  }
}
  
struct CreateDatabaseSchemaMigration: Migration {
  /** Create the basic database schema conforming to the original cache system. */
  
  func shouldApply(on db: any SQLDatabase) async throws -> Bool {
    let tablesToCheck = ["regions", "resources", "tiles", "region_resources"]
    
    let allTables = try await db.raw("SELECT name FROM sqlite_master WHERE type='table'").all(decodingColumn: "name", as: String.self)
    
    let existingTables = allTables.filter { tablesToCheck.contains($0) }
    
    if existingTables.count == tablesToCheck.count {
      // All tables already exist, skip migration
    } else if existingTables.count > 0 {
      let tbl = existingTables.joined(separator: ", ")
      throw RuntimeError.databaseError("Some tables already exist (\(tbl)) but the database is incompletely defined")
    }
    return existingTables.count == 0
  }
  
  func run(on db: any SQLDatabase) async throws {
    try await runSQL(db, statements: databaseSchemaSQL)
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

struct CreateDataSizeColumnMigration: Migration {
  /** Create the basic database schema conforming to the original cache system. */
  
  let tableName: String
  
  init(tableName: String) {
    self.tableName = tableName
  }
  
  func shouldApply(on db: any SQLDatabase) async throws -> Bool {
    // Check if the data_size column already exists in the specified table
    return !(try await hasColumn(db, tableName: tableName, columnName: "data_size"))
  }
  
  func run(on db: any SQLDatabase) async throws {
    try await runSQL(db, statements: "ALTER TABLE \(tableName) ADD COLUMN data_size INTEGER NOT NULL DEFAULT 0")
    try await runSQL(db, statements: "UPDATE \(tableName) SET data_size = coalesce(length(data), 0)")
  }
  
  var name: String {
    return "Create data_size column - \(tableName)"
  }
}

struct CreateIndicesMigration: Migration {
  /** Create the basic database schema conforming to the original cache system. */
  func run(on db: any SQLDatabase) async throws {
    // language=SQL
    let buildIndicesSQL = """
      CREATE INDEX IF NOT EXISTS region_tiles_tile_id on region_tiles (tile_id);
      CREATE INDEX IF NOT EXISTS tiles_accessed on tiles (accessed);
      CREATE INDEX IF NOT EXISTS tiles_url_template on tiles (url_template);
      CREATE INDEX IF NOT EXISTS tiles_spatial_index ON tiles (url_template, x, y, z);
    
      CREATE INDEX IF NOT EXISTS region_tiles_region_id ON region_tiles(region_id, tile_id);
      CREATE INDEX IF NOT EXISTS tiles_id_data_size ON tiles(id, data_size);
      CREATE INDEX IF NOT EXISTS region_resources_region_id ON region_resources(region_id, resource_id);
      CREATE INDEX IF NOT EXISTS resources_id_data_size ON resources(id, data_size);
    """
    
    // Build indices
    try await runSQL(db, statements: buildIndicesSQL)
  }
  
  func shouldApply(on db: any SQLDatabase) async throws -> Bool {
    return true
  }
}

func indexExists(_ database: any SQLDatabase, indexName: String) async throws -> Bool {
  let result = try await database.raw("SELECT name FROM sqlite_master WHERE type='index' AND name = \(bind: indexName)").first(decodingColumn: "name", as: String.self)
  return result != nil
}

func hasColumn(_ database: any SQLDatabase, tableName: String, columnName: String) async throws -> Bool {
  let result = try await database.raw("SELECT 1 FROM pragma_table_info(\(bind: tableName)) WHERE name = \(bind: columnName)").first()
  return result != nil
}

func runSQL(_ database: any SQLDatabase, statements: String) async throws {
  // Run raw SQL statements
  let queries = statements.split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
  for query in queries {
    try await database.raw(SQLQueryString(query)).run()
  }
}
