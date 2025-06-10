//
//  CreateCache.swift
//  MobileMapCache
//
//  Created by Daven Quinn on 5/19/25.
//

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
    for: polygon, minZoom: definition.minZoom, maxZoom: definition.maxZoom)

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
    for: polygon, minZoom: definition.minZoom, maxZoom: definition.maxZoom)
  let client = app.client

  await withTaskGroup(of: Void.self) { taskGroup in
    for tile in tiles {
      taskGroup.addTask {
        let url = definition.style.styleURL  // Assuming styleURL contains the base URL for tiles
        let tileURL = "\(url)/\(tile.z)/\(tile.x)/\(tile.y).pbf"

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
