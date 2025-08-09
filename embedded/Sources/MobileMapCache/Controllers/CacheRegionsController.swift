//
//  CacheRegionsController.swift
//  MobileMapCache
//
//  Created by Daven Quinn on 5/17/25.
//

import Fluent
import FluentSQL
import Vapor

// definition: {"style_url":"http://localhost:50051/dynamic-styles/rockd-cache.v1.0.satellite.json","min_zoom":0.0,"max_zoom":0.0,"pixel_ratio":2.0,"glyphs_rasterization":1,"geometry":{"type":"Polygon","coordinates":[[[-180.0,-90.0],[180.0,-90.0],[180.0,90.0],[-180.0,90.0],[-180.0,-90.0]]]}}
// description: {"layers":["satellite"],"styleVersion":"1.0","updated":"2025-01-10T05:37:00.000Z","name":"rockd-cache.v1.0.satellite","created":"2025-01-10T05:37:00.000Z"}

struct MBXCacheRegionDefinition: Content {
  /** Cache region definition for a Mapbox Maps SDK cache */
  let styleURL: String
  let minZoom: Double
  let maxZoom: Double
  let pixelRatio: Double
  let glyphsRasterization: Int
  let geometry: PolygonGeometry

  struct PolygonGeometry: Content {
    let type: String
    let coordinates: [[[Double]]]
  }

  enum CodingKeys: String, CodingKey {
    case styleURL = "style_url"
    case minZoom = "min_zoom"
    case maxZoom = "max_zoom"
    case pixelRatio = "pixel_ratio"
    case glyphsRasterization = "glyphs_rasterization"
    case geometry
  }
}

struct MBXCacheRegionDescription: Content {
  let layers: [String]
  let styleVersion: String
  let updated: String
  let name: String
  let created: String
}

struct MBXCacheRegion: Content {
  let id: Int
  let definition: MBXCacheRegionDefinition
  let description: MBXCacheRegionDescription
}

struct CacheRegionsController: RouteCollection {

  let connectionManager = WebSocketConnectionManager()

  func boot(routes: any RoutesBuilder) throws {
    let regions = routes.grouped("regions")

    regions.get(use: self.index)
    regions.post(use: self.create)
    regions.webSocket("socket", onUpgrade: self.webSocket)
  }

  @Sendable
  func index(req: Request) async throws -> [MBXCacheRegion] {
    // Get a list of regions
    let sql: SQLQueryString = """
      SELECT id, definition, description FROM regions
      """

    guard let db = req.db as? any SQLDatabase else {
      throw Abort(.internalServerError, reason: "Database is not SQLDatabase")
    }

    // Description is a JSON string
    let regions = try await db.raw(sql)
      .all(decoding: MBXCacheRegion.self)

    return regions
  }

  // Route to create a cache region
  @Sendable
  func create(req: Request) async throws -> MBXCacheRegion {
    let region = try req.content.decode(MBXCacheRegion.self)

    // Save the region to the database
    guard let db = req.db as? any SQLDatabase else {
      throw Abort(.internalServerError, reason: "Database is not SQLDatabase")
    }

    try await db.raw(
      "INSERT INTO regions (definition, description) VALUES (\(bind: region.definition), \(bind: region.description))"
    ).run()

    // Start the download process (will run outside of the request lifecycle)

    return region
  }

  func webSocket(request: Request, ws: WebSocket) {
    // Add the new WebSocket connection to your connection manager
    Task {
      await self.connectionManager.add(ws)
      request.logger.info("WebSocket connected")
    }
    
    ws.onClose.whenComplete { result in
      Task {
        await self.connectionManager.remove(ws)
      }
      switch result {
      case .success:
        request.logger.info("WebSocket closed")
      case .failure(let error):
        request.logger.info("WebSocket closed with error: \(error)")
      }
    }
  }

  private func performBackgroundTask(with ws: WebSocket, receivedText: String) async {
    // Simulate a long-running task
    try? await Task.sleep(nanoseconds: 5_000_000_000)  // 5 seconds

    // Send a message back to the client once the task is complete
    do {
      try await ws.send("Background task finished processing: \(receivedText)")
    } catch {
      print("Failed to send message: \(error)")
    }
  }
}

// You might define a class or actor to manage WebSocket connections
actor WebSocketConnectionManager {
  private var connections: [WebSocket] = []

  func add(_ ws: WebSocket) {
    connections.append(ws)
  }

  func remove(_ ws: WebSocket) {
    connections.removeAll(where: { $0 === ws })
  }

  func sendToAll(_ message: String) async throws {
    for ws in connections {
      try await ws.send(message)
    }
  }
}
