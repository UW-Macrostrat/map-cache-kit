//
//  CreateCache.swift
//  MobileMapCache
//
//  Created by Daven Quinn on 5/19/25.
//

import Fluent
import FluentSQLiteDriver
import GEOSwift
import SwiftTileMatrix
import Vapor

/**
 Frontend typescript types

 export interface CacheCreationData<Metadata extends object = {}> {
   minZoom: number;
   maxZoom: number;
   geometry: GeoJSON.Geometry;
   styleURL: string;
   metadata: Metadata;
 }

 export interface OfflineRegionStatus {
   completedResourceCount: number;
   completedResourceSize: number;
   requiredResourceCount: number;
   completedTileCount: number;
   completedTileSize: number;
   requiredTileCount: number;
   downloadState: "active" | "inactive";
   requiredResourceCountIsPrecise: boolean;
 }
 */

enum StyleDefinition: Codable {
  case jsonData(String)
  case styleURL(String)
}

struct CacheRegionDefinition: Codable {
  var style: StyleDefinition
  var minZoom: Int
  var maxZoom: Int
  var pixelRatio: Int
  var glyphsRasterization: Int
  var geometry: Polygon

  enum CodingKeys: String, CodingKey {
    case style
    case minZoom = "min_zoom"
    case maxZoom = "max_zoom"
    case pixelRatio = "pixel_ratio"
    case glyphsRasterization = "glyphs_rasterization"
    case geometry
  }
}

enum RuntimeError: Error {
  case invalidArgument(String)
}

func getCacheRegion(from definition: CacheRegionDefinition) async throws {
  // Validate the definition
  guard definition.minZoom >= 0 else {
    throw RuntimeError.invalidArgument("Minimum zoom level must be greater than or equal to 0")
  }

  guard definition.maxZoom >= definition.minZoom else {
    throw RuntimeError.invalidArgument(
      "Maximum zoom level must be greater than or equal to minimum zoom level")
  }

  // Convert the geometry to a GEOSwift Polygon
  let polygon = definition.geometry

  // Figure out which sources to download

  // Download font stacks, glyphs, etc.

  // Get the intersecting tiles
  let tiles = try getIntersectingTiles(
    for: polygon.geometry, minZoom: definition.minZoom, maxZoom: definition.maxZoom
  )

  // Download tiles with rate limiting

}

func downloadTileCache(with app: Application, using definition: CacheRegionDefinition) async throws
{
  // Validate the definition
  guard definition.minZoom >= 0 else {
    throw RuntimeError.invalidArgument("Minimum zoom level must be greater than or equal to 0")
  }

  guard definition.maxZoom >= definition.minZoom else {
    throw RuntimeError.invalidArgument(
      "Maximum zoom level must be greater than or equal to minimum zoom level")
  }

  // Convert the geometry to a GEOSwift Polygon
  let polygon = definition.geometry

  // Get the intersecting tiles
  let tiles = try getIntersectingTiles(
    for: polygon.geometry, minZoom: definition.minZoom, maxZoom: definition.maxZoom)
  let client = app.client

  // Get the tile URL templates from the style definition
  let tileURLTemplates = try await getTileURLTemplatesFromStyle(
    with: app, style: definition.style)

  await withTaskGroup(of: Void.self) { taskGroup in
    for tile in tiles {
      for url in tileURLTemplates {
        // Replace the placeholders in the URL with the tile coordinates
        let tileURL =
          url
          .replacingOccurrences(of: "{z}", with: "\(tile.z)")
          .replacingOccurrences(of: "{x}", with: "\(tile.x)")
          .replacingOccurrences(of: "{y}", with: "\(tile.y)")

        // Add a task to download the tile

        taskGroup.addTask {
          // Download the tile
          do {
            let response = try await client.get(URI(string: tileURL))
            guard response.status == .ok else {
              print("Failed to download tile at \(tileURL): \(response.status)")
              return
            }

            let data = response.body?.readableBytesView
            // Process the tile data (e.g., save to disk or database)
            print("Downloaded tile at \(tileURL)")
          } catch {
            print("Error downloading tile at \(tileURL): \(error)")
          }
        }
      }
    }
  }
}

func getJSONForStyle(
  with app: Application,
  style: StyleDefinition
) async throws -> Data {
  switch style {
  case .jsonData(let json):
    guard let data = json.data(using: .utf8) else {
      throw RuntimeError.invalidArgument("Failed to convert JSON string to Data")
    }
    return data
  case .styleURL(let url):
    // Fetch the JSON from the URL
    let client = try await app.client.get(URI(string: url))
    guard client.status == .ok, let body = client.body else {
      throw RuntimeError.invalidArgument("Failed to fetch style JSON from URL: \(url)")
    }

    guard let data = body.getData(at: 0, length: body.readableBytes) else {
      throw RuntimeError.invalidArgument("Failed to convert response body to Data")
    }
    return data
  }
}

func getTileURLTemplatesFromStyle(
  with app: Application,
  style: StyleDefinition
) async throws -> [String] {
  var templates: [String] = []

  let data = try await getJSONForStyle(with: app, style: style)

  // Parse the JSON to extract tile URL templates

  if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
    let sources = jsonObject["sources"] as? [String: Any]
  {
    for (_, source) in sources {
      if let sourceDict = source as? [String: Any] {
        if let tiles = sourceDict["tiles"] as? [String] {
          templates.append(contentsOf: tiles)
        }
      }
    }
  }

  return templates
}

func persistTileToDatabase(
  db: Database, tile: TileCoord, data: Data, compressed: Bool, regionId: Int
) async throws {
  let sql = """
    WITH inserted_tile AS (
      INSERT INTO tiles (x, y, z, data, compressed)
      VALUES ($1, $2, $3, $4, $5)
      ON CONFLICT (x, y, z) DO NOTHING
      RETURNING x, y, z
    )
    INSERT INTO region_tiles (region_id, x, y, z)
    SELECT $6, x, y, z
    FROM inserted_tile
    ON CONFLICT (region_id, x, y, z) DO NOTHING
    """

  // Cast to SQLDatabase
  guard let db = db as? SQLiteDatabase else {
    throw RuntimeError.invalidArgument("Database must be an SQLDatabase")
  }

  let params: [SQLiteData] = [
    .integer(tile.x),
    .integer(tile.y),
    .integer(tile.z),
    .blob(ByteBuffer(data: data)),
    .integer(compressed ? 1 : 0),
    .integer(regionId),
  ]

  _ = try await db.query(sql, params)
}

func persistResourceToDatabase(
  db: Database, url: String, data: Data, compressed: Bool, kind: ResourceKind, regionId: Int
) async throws {
  let sql = """
    WITH inserted_resource AS (
      INSERT INTO resources (url, data, compressed, kind)
      VALUES ($1, $2, $3, $4)
      ON CONFLICT (url) DO NOTHING
      RETURNING url
    )
    INSERT INTO region_resources (region_id, url)
    SELECT $5, url
    FROM inserted_resource
    ON CONFLICT (region_id, url) DO NOTHING
    """

  guard let db = db as? SQLiteDatabase else {
    throw RuntimeError.invalidArgument("Database must be an SQLDatabase")
  }

  let params: [SQLiteData] = [
    .text(url),
    .blob(ByteBuffer(data: data)),
    .integer(compressed ? 1 : 0),
    .integer(kind.rawValue),
    .integer(regionId),
  ]

  _ = try await db.query(sql, params)
}

func getIntersectingTiles(for geom: Geometry, minZoom: Int, maxZoom: Int) throws -> [TileCoord] {
  let parentTile = try getParentTile(for: geom)

  if minZoom < 0 {
    throw RuntimeError.invalidArgument("Minimum zoom level must be greater than or equal to 0")
  }

  var tiles: [TileCoord] = []
  // Prevents us from having to calculate intersections for all tiles
  var parentTiles: [TileCoord] = [parentTile]
  var currentLevelTiles: [TileCoord] = []

  for zoom in stride(from: min(minZoom, parentTile.z), through: maxZoom, by: 1) {
    let deltaZ = parentTile.z - zoom
    let factor = Double.pow(2, deltaZ)
    let xTile = Int(Double(parentTile.x) * factor)
    let yTile = Int(Double(parentTile.y) * factor)

    // number of tiles at this zoom level
    let xTiles: Int = max(1 << deltaZ, 1)
    let yTiles: Int = max(1 << deltaZ, 1)

    currentLevelTiles = []

    if zoom <= parentTile.z {
      tiles.append(TileCoord(xTile, yTile, zoom))
      parentTiles = [TileCoord(xTile, yTile, zoom)]
    } else {
      for tile in parentTiles {
        // split the tile into 4
        for dx in 0..<2 {
          for dy in 0..<2 {
            let newX = tile.x * 2 + dx
            let newY = tile.y * 2 + dy
            // Check that all tiles intersect the geometry
            let newTile = TileCoord(newX, newY, zoom)
            if try geom.intersects(newTile.envelope) {
              // Only add the tile if it intersects the geometry
              // This prevents adding tiles that are not needed
              // at this zoom level
              currentLevelTiles.append(newTile)
            }
          }
        }
      }
      parentTiles = currentLevelTiles
      tiles.append(contentsOf: currentLevelTiles)
    }
  }
  return tiles
}

extension TileCoord {
  func contains(_ other: TileCoord) -> Bool {
    if self.x == other.x && self.y == other.y && self.z == other.z {
      return true
    }
    if self.z > other.z {
      return false
    }
    let zoomDiff = self.z - other.z
    let factor = 1 << zoomDiff
    let xFactor = other.x / factor
    let yFactor = other.y / factor
    return self.x == xFactor && self.y == yFactor
  }
}

func getParentTile(for geom: Geometry) throws -> TileCoord {
  // Geometry is assumed to be in EPSG:4326
  let env = try geom.envelope()

  // Get x range and y range

  let bottomLeft = epsg4326ToWebMercator(point: env.minXMinY)
  let topRight = epsg4326ToWebMercator(point: env.maxXMaxY)

  let xSize = topRight.x - bottomLeft.x
  let ySize = topRight.y - bottomLeft.y

  // Get max size
  let maxSize = max(xSize, ySize)

  let fracWidth = maxSize / webMercatorGridSize

  let zoomLevel = Int(abs(.log2(fracWidth)))

  let tileSize = webMercatorGridSize / Double(1 << zoomLevel)
  let xTile = Int((bottomLeft.x + webMercatorGridSize / 2.0) / tileSize)
  let yTile = Int((bottomLeft.y + webMercatorGridSize / 2.0) / tileSize)

  return TileCoord(xTile, yTile, zoomLevel)
}

func epsg4326ToWebMercator(point: Point) -> Point {
  // Grid size (overall circumerence)
  let gridSize = webMercatorGridSize
  let d2r: Double = .pi / 180

  let lonRadians: Double = point.x * d2r
  let latRadians: Double = point.y * d2r

  return Point(
    x: (lonRadians * 2.0 * .asinh(.exp(lonRadians))) * gridSize / 2.0,
    y: .log(.tan((.pi + latRadians) / 4.0)) * gridSize / 2.0
  )
}
