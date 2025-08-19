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
  app.routes.defaultMaxBodySize = "10mb"
  
  try app.register(collection: CacheRegionsController())
  try app.register(collection: CachedTileController())
  
  let cfg = CORSMiddleware.Configuration(
    allowedOrigin: .all,
    allowedMethods: [.GET, .POST, .PUT, .OPTIONS, .DELETE, .PATCH],
    allowedHeaders: [.accept, .authorization, .contentType, .origin, .xRequestedWith, .userAgent, .accessControlAllowOrigin, "x-cache-domain", "x-cache", "cache-control, content-encoding"],
    
  )
  
  app.middleware.use(CORSMiddleware(configuration: cfg))
}
