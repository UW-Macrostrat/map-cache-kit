import Fluent
import FluentSQLiteDriver
import NIOSSL
import Vapor

struct AppConfig {
  var mapboxAPIToken: String?
}


struct ConfigurationKey: StorageKey {
  typealias Value = AppConfig
}

struct DownloadTaskStoreKey: StorageKey {
  typealias Value = [Int: Task<Void,Never>]
}

extension Application {
  var config: AppConfig {
    get throws {
      guard let res = self.storage.get(ConfigurationKey.self) else {
        throw RuntimeError.configurationError("AppConfig not set in application storage")
      }
      return res
    }
  }
  
  var taskStore: [Int: Task<Void,Never>] {
    get {
      self.storage.get(DownloadTaskStoreKey.self) ?? [:]
    }
    set {
      self.storage.set(DownloadTaskStoreKey.self, to: newValue)
    }
  }
  
  func addDownloadTask(id: Int, task: Task<Void,Never>) {
    self.taskStore[id] = task
  }
  
  func cancelDownloadTask(id: Int) {
    if let task = self.taskStore.removeValue(forKey: id) {
      task.cancel()
    }
  }
}

// configures your application
public func configure(_ app: Application, cacheDatabase: SQLiteConfiguration) async throws {
  // uncomment to serve files from /Public folder
  // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
  //
 
  let apiToken = Environment.get("MAPBOX_API_KEY")
    
  let cfg = AppConfig(mapboxAPIToken: apiToken)
  await app.storage.setWithAsyncShutdown(ConfigurationKey.self, to: cfg)
  
  print("Configuring MobileMapCache with database: \(cacheDatabase.storage)")

  app.databases.use(DatabaseConfigurationFactory.sqlite(cacheDatabase), as: .sqlite)
  
  //app.migrations.add(CreateTodo())
  app.migrations.add(CreateDatabaseSchema())

  // register routes
  try routes(app)
}
