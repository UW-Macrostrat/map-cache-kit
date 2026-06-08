import Fluent
import Vapor
import FluentSQL

struct CacheSystemInfo: Content {
  let name: String
  let version: String
}

struct CacheLifcycleManager: LifecycleHandler {
  let connectionManager: WebSocketConnectionManager
  
  init(connectionManager: WebSocketConnectionManager) {
    self.connectionManager = connectionManager
  }
  
  func shutdownAsync(_ application: Application) async {
    application.logger.info("Shutting down cache system, closing all WebSocket connections")
    do {
      try await connectionManager.closeAllConnections()
    } catch {
      application.logger.report(error: error)
    }
  }
}
