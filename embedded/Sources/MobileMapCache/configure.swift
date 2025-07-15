import Fluent
import FluentSQLiteDriver
import NIOSSL
import Vapor

// configures your application
public func configure(_ app: Application, cacheDatabase: SQLiteConfiguration) async throws {
  // uncomment to serve files from /Public folder
  // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
  //
  
  print("Configuring MobileMapCache with database: \(cacheDatabase.storage)")

  app.databases.use(DatabaseConfigurationFactory.sqlite(cacheDatabase), as: .sqlite)

  //app.migrations.add(CreateTodo())
  app.migrations.add(CreateDatabaseSchema())


  // register routes
  try routes(app)
}
