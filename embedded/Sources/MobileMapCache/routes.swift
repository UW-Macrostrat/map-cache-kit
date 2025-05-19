import Fluent
import Vapor

func routes(_ app: Application) throws {
  app.get { req async in
    "It works!"
  }
  
  app.get("hello") { req async -> String in
    "Hello, world!"
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
