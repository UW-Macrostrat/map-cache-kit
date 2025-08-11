import Fluent
import Vapor
import FluentSQL

struct CacheSystemInfo: Content {
  let name: String
  let version: String
}

func routes(_ app: Application) throws {
  app.get { req async in
    return CacheSystemInfo(name: "Rockd cache system", version: "1.1.0")
  }
  
  app.get("info") { req async throws in
    guard let db = req.db as? any SQLDatabase else {
      throw Abort(.internalServerError, reason: "Database is not SQLDatabase")
    }
    
    let sql: SQLQueryString = """
      WITH resources_count AS (
        SELECT
          sum(length(data)) resource_size,
          count(data) resource_count
        FROM resources
      ), tiles_count AS (
        SELECT
          sum(length(data)) tile_size,
          count(data) tile_count
        FROM tiles
      )
      SELECT
        rc.resource_size,
        rc.resource_count,
        tc.tile_size,
        tc.tile_count
      FROM resources_count rc, tiles_count tc;
    """
    
    guard let res = try await db.raw(sql).first(decoding: CachedAssetsInfo.self) else {
      throw Abort(.internalServerError, reason: "Failed to fetch cached assets info")
    }
    
    return res
    
  }


  try app.register(collection: CacheRegionsController())
  try app.register(collection: CachedTileController())
  
  let cfg = CORSMiddleware.Configuration(
    allowedOrigin: .all,
    allowedMethods: [.GET, .POST, .PUT, .OPTIONS, .DELETE, .PATCH],
    allowedHeaders: [.accept, .authorization, .contentType, .origin, .xRequestedWith, .userAgent, .accessControlAllowOrigin, "x-cache-domain", "x-cache", "cache-control, content-encoding"],
    
  )
  
  app.middleware.use(CORSMiddleware(configuration: cfg))
}
