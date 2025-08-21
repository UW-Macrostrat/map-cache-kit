import Fluent
import FluentSQLiteDriver
import NIOSSL
import Vapor
import NIOCore

public struct AppConfig: Sendable {
  let mapboxAPIToken: String?
  let staticMapStyle: String
  let maxConcurrentHTTPConnections: Int
  // Time between http requests during cache downloading
  let httpRequestTimeout: TimeAmount
  let maxNumberOfRegions: Int
  // If we don't want to download the entire unicode range for each font, we can limit the maximum code point
  let maxCodePoint: Int
  let autoMigrate: Bool
  let methods: any AppInjectedMethods
  
  public init(
    mapboxAPIToken: String?,
    staticMapStyle: String = "mapbox://styles/jczaplewski/cl3w3bdai001f14ob27ckmpxz",
    maxConcurrentHTTPConnections: Int = 4,
    httpRequestTimeout: TimeAmount = .milliseconds(50),
    maxNumberOfRegions: Int = 10,
    maxCodePoint: Int = 65535,
    autoMigrate: Bool = true,
    methods: any AppInjectedMethods = DefaultInjectedMethods()
  ) {
    self.mapboxAPIToken = mapboxAPIToken
    self.staticMapStyle = staticMapStyle
    self.maxConcurrentHTTPConnections = maxConcurrentHTTPConnections
    self.httpRequestTimeout = httpRequestTimeout
    self.maxNumberOfRegions = maxNumberOfRegions
    self.maxCodePoint = maxCodePoint
    self.autoMigrate = autoMigrate
    self.methods = methods
  }
}

public protocol AppInjectedMethods: Sendable {
  func addParams(app: Application, for asset: RequestedAsset) throws -> [String: String?]
}

extension AppInjectedMethods {
  public func addParams(app: Application, for asset: RequestedAsset) throws -> [String: String?] {
    if asset.isMapboxAsset {
      let mapboxToken = try app.config.mapboxAPIToken
      return ["access_token": mapboxToken]
    }
    return [:]
  }
}

public struct DefaultInjectedMethods: AppInjectedMethods {
  public init() {}
}


struct ConfigurationKey: StorageKey {
  typealias Value = AppConfig
}

struct DownloadTaskStoreKey: StorageKey {
  typealias Value = [Int: Task<Void, any Error>]
}

struct ConcurrentDownloadManagerKey: StorageKey {
  typealias Value = ConcurrentDownloadManager
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

  var downloadManger: ConcurrentDownloadManager {
    get throws {
      let cfg = try self.config
      if let manager = self.storage.get(ConcurrentDownloadManagerKey.self) {
        return manager
      } else {
        let manager = ConcurrentDownloadManager(
          maxConcurrentDownloads: cfg.maxConcurrentHTTPConnections
        )
        self.storage.set(ConcurrentDownloadManagerKey.self, to: manager)
        return manager
      }
    }
  }

  var taskStore: [Int: Task<Void, any Error>] {
    get {
      self.storage.get(DownloadTaskStoreKey.self) ?? [:]
    }
    set {
      self.storage.set(DownloadTaskStoreKey.self, to: newValue)
    }
  }

  func addDownloadTask(id: Int, task: Task<Void, any Error>) {
    self.taskStore[id] = task
  }

  func cancelDownloadTask(id: Int) {
    if let task = self.taskStore.removeValue(forKey: id) {
      task.cancel()
    }
  }
  
  func getDatabase() throws -> any SQLDatabase {
    guard let db = self.db as? any SQLDatabase else {
      throw RuntimeError.databaseError("Database is not an SQLDatabase")
    }
    return db
  }
}

// configures your application
public func configure(_ app: Application, cacheDatabase: SQLiteConfiguration, config: AppConfig) async throws {
  // uncomment to serve files from /Public folder
  // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
  //  
  await app.storage.setWithAsyncShutdown(ConfigurationKey.self, to: config)

  app.logger.info("Configuring MapCacheKit with database: \(cacheDatabase.storage)")

  app.databases.use(DatabaseConfigurationFactory.sqlite(cacheDatabase), as: .sqlite)

  //app.migrations.add(CreateTodo())
  app.migrations.add(CreateDatabaseSchema())
  
  if config.autoMigrate {
    // Auto-migrate database if enabled
    try await app.autoMigrate()
  }
    
  // register routes
  try routes(app)
}
