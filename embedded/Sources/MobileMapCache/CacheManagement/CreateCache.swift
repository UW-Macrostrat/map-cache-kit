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
  case databaseError(String)
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

struct CandidateTile {
  let x: Int
  let y: Int
  let z: Int
  let urlTemplate: String
}

struct RegionTileInfo {
  let tilesToDownload: [CandidateTile]
  let tilesAlreadyDownloaded: [CandidateTile]
  let totalSizeOfTilesDownloaded: Int64
}

struct RegionResourceInfo {
  let resourcesToDownload: [RequestedResource]
  let resourcesAlreadyDownloaded: [RequestedResource]
  let totalSizeOfResourcesDownloaded: Int64
}

struct RegionAssetsToDownload {
  let tiles: RegionTileInfo
  let resources: RegionResourceInfo
}

func getRegionAssets(
  with app: Application, using definition: CacheRegionDefinition
) async throws -> RegionAssetsToDownload {
  let tiles = try await getTilesToDownload(with: app, using: definition)
  
  // Get the resources to download
  let resources = try await getResourcesToDownload(with: app, using: definition)

  return RegionAssetsToDownload(tiles: tiles, resources: resources)
}


func getTilesToDownload(with app: Application, using definition: CacheRegionDefinition) async throws -> RegionTileInfo {
  // Convert the geometry to a GEOSwift Polygon
  let polygon = definition.geometry
  
  // Get the intersecting tiles
  let tiles = try getIntersectingTiles(
    for: polygon.geometry, minZoom: definition.minZoom, maxZoom: definition.maxZoom)
  
  // Get the tile URL templates from the style definition
  let tileLayerDefs = try await getCacheableTileLayersFromStyle(
    with: app, style: definition.style)
  
  // Get all tiles that may need to be downloaded
  var candidateTiles: [CandidateTile] = []
  
  for tile in tiles {
    for lyr in tileLayerDefs {
      // Special case for raster and raster-dem tiles (mapbox): no zoom 0 tiles for these types
      if (lyr.type == .raster || lyr.type == .rasterDem) && tile.z == 0 {
        continue
      }
      // Add the candidate tile
      candidateTiles.append(CandidateTile(x: tile.x, y: tile.y, z: tile.z, urlTemplate: lyr.urlTemplate))
    }
  }
  
  guard let db = app.db as? any SQLDatabase else {
    throw RuntimeError.databaseError("Database is not an SQLDatabase")
  }
  
  var tilesToDownload: [CandidateTile] = []
  var tilesAlreadyDownloaded: [CandidateTile] = []
  var totalSizeOfTilesDownloaded: Int64 = 0
  
  // already downloaded tiles
  for candidate in candidateTiles {
    let sql: SQLQueryString = """
      SELECT length(data) size FROM tiles
      WHERE x = \(bind: candidate.x)
        AND y = \(bind: candidate.y)
        AND z = \(bind: candidate.z)
        AND url_template = \(bind: candidate.urlTemplate)
      LIMIT 1
      """
    if let tileSize = try await db.raw(sql).first(decodingColumn: "size", as: Int64.self) {
      totalSizeOfTilesDownloaded += tileSize
      tilesAlreadyDownloaded.append(candidate)
    } else {
    // If the tile is not in the database, we need to download it
      tilesToDownload.append(candidate)
    }
  }
  
  return RegionTileInfo(
    tilesToDownload: tilesToDownload,
    tilesAlreadyDownloaded: tilesAlreadyDownloaded,
    totalSizeOfTilesDownloaded: totalSizeOfTilesDownloaded
  )
}


func getResourcesToDownload(
  with app: Application, using definition: CacheRegionDefinition
) async throws -> RegionResourceInfo {

  let jsonData = try await getJSONForStyle(with: app, style: definition.style)
  // decode the style
  let styleSpec = try JSONDecoder().decode(StyleSpec.self, from: jsonData)
  
  let resources = try findResourcesRequestedByMapboxStyle(spec: styleSpec, options: ResourceFindOptions(maxCodePoint: 255))

  // Check which resources are already downloaded
  var resourcesToDownload: [RequestedResource] = []
  var resourcesAlreadyDownloaded: [RequestedResource] = []
  var totalSizeOfResourcesDownloaded: Int64 = 0
  
  for resource in resources {
    // Check if the resource is already in the database
    if let size = try await findResourceInDatabase(
      db: app.db, url: resource.urlTemplate, kind: resource.kind) {
      // Resource already exists
      totalSizeOfResourcesDownloaded += size
      resourcesAlreadyDownloaded.append(resource)
    } else {
      // Resource needs to be downloaded
      resourcesToDownload.append(resource)
    }
  }
  
  return RegionResourceInfo(
    resourcesToDownload: resourcesToDownload,
    resourcesAlreadyDownloaded: resourcesAlreadyDownloaded,
    totalSizeOfResourcesDownloaded: totalSizeOfResourcesDownloaded
  )
}



func findResourceInDatabase(
  db: any Database, url: String, kind: ResourceKind
) async throws -> Int64? {
  let sql: SQLQueryString = """
    SELECT length(data) as size
    FROM resources
    WHERE url = \(bind: url) AND kind = \(bind: kind.rawValue)
    LIMIT 1
    """
  
  guard let db = db as? any SQLDatabase else {
    throw RuntimeError.databaseError("Database is not an SQLDatabase")
  }
  
  if let row = try await db.raw(sql).first(decodingColumn: "size", as: Int64.self) {
    return row
  }
  return nil
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
  
  let client = app.client

  let spec = try await getTilesToDownload(with: app, using: definition)

  await withTaskGroup(of: Void.self) { taskGroup in
    for tile in spec.tilesToDownload {
      // Replace the placeholders in the URL with the tile coordinates
      let tileURL = tile.urlTemplate
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

enum SourceType: String, Codable {
  case vector = "vector"
  case raster = "raster"
  case rasterDem = "raster-dem"
  case geojson = "geojson"
  case image = "image"
  case video = "video"
}

struct CacheLayerDefinition {
  let type: SourceType
  // Cache key used to store tiles in the database
  let urlTemplate: String
}

func getCacheableTileLayersFromStyle(
  with app: Application,
  style: StyleDefinition
) async throws -> [CacheLayerDefinition] {
  var defs: [CacheLayerDefinition] = []

  let data = try await getJSONForStyle(with: app, style: style)

  // Parse the JSON to extract tile URL templates

  if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
    let sources = jsonObject["sources"] as? [String: Any]
  {
    for (_, source) in sources {
      guard let sourceDict = source as? [String: Any],
            let st = sourceDict["type"] as? String,
            let sourceType = SourceType(rawValue: st)
      else {
        throw RuntimeError.invalidArgument(
          "Invalid source format in style JSON: \(source)"
        )
      }
        
      if let tiles = sourceDict["tiles"] as? [String] {
        if tiles.count != 1 {
          throw RuntimeError.invalidArgument(
            "Expected exactly one tile URL template for source type \(sourceType), found \(tiles.count) (multiple tile URLs are not yet supported)"
          )
        }
        defs.append(CacheLayerDefinition(type: sourceType, urlTemplate: tiles[0]))
      } else if let urlTemplate = sourceDict["url"] as? String {
        // We are working with a tilejson file and need to infer the tile URL templates
        // We could do this by fetching and parsing the tileJSON also, but tileJSONs passed by mapbox
        // don't pass the correct requests anyway
        let url: String = try inferTileURLTemplate(
          from: urlTemplate, sourceType: sourceType
        )
        defs.append(CacheLayerDefinition(type: sourceType, urlTemplate: url))
      }
    }
  }

  return defs
}

func inferTileURLTemplate(from tileJSONURL: String, sourceType: SourceType) throws -> String {
  if !tileJSONURL.starts(with: "mapbox://") {
    throw RuntimeError.invalidArgument("Inferring tile URLs from non-Mapbox TileJSONs is not supported at the moment")
  }
  
  switch sourceType {
  case .vector:
    return tileJSONURL.replacingOccurrences(of: "mapbox://", with: "mapbox://tiles/") + "/{z}/{x}/{y}.vector.pbf"
  case .raster:
    return tileJSONURL.replacingOccurrences(of: "mapbox://", with: "mapbox://tiles/") + "/{z}/{x}/{y}{ratio}.png"
  case .rasterDem:
    // Raster DEMs do not support ratios
    return tileJSONURL.replacingOccurrences(of: "mapbox://", with: "mapbox://tiles/") + "/{z}/{x}/{y}.png"
  default:
    throw RuntimeError.invalidArgument("\(sourceType) sources are not supported for tileJSON inference")
  }
}

func persistTileToDatabase(
  db: any Database, tile: TileCoord, data: Data, compressed: Bool, regionId: Int
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
  guard let db = db as? any SQLiteDatabase else {
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
  db: any Database, url: String, data: Data, compressed: Bool, kind: ResourceKind, regionId: Int
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

  guard let db = db as? any SQLiteDatabase else {
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
  
  // Filter tiles that are less than the minimum zoom
  return tiles.filter { $0.z >= minZoom }  
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
  var tileCoord = TileCoord(0, 0, 0)
  
  // Ensure the tile coord envelope is clipped to the web mercator bounds
  guard let geom1 = try tileCoord.envelope.intersection(with: geom) else {
    throw RuntimeError.invalidArgument("Geometry does not intersect with tile matrix bounds")
  }
    
  // Geometry is assumed to be in EPSG:4326
  let env = try geom1.envelope()

  // Get x range and y range

  let bottomLeft = epsg4326ToWebMercator(point: env.minXMinY)
  let topRight = epsg4326ToWebMercator(point: env.maxXMaxY)
  
  let webMercatorEnvelope = Envelope(
    minX: bottomLeft.x,
    maxX: topRight.x,
    minY: bottomLeft.y,
    maxY: topRight.y
  )
  
  while tileCoord.z < 30 {
    // Check if any of the child tiles cover the geometry
    let x0 = tileCoord.x * 2
    let y0 = tileCoord.y * 2
    let z = tileCoord.z + 1
    let childTiles = [
      TileCoord(x0, y0, z),     // Bottom-left
      TileCoord(x0 + 1, y0, z), // Bottom-right
      TileCoord(x0, y0 + 1, z), // Top-left
      TileCoord(x0 + 1, y0 + 1, z) // Top-right
    ]
    
    for childTile in childTiles {
      if try childTile.envelope.covers(webMercatorEnvelope) {
        tileCoord = childTile
        break
      }
    }
    // If we didn't find a child tile that covers the geometry, we can stop
    return tileCoord
  }

  throw RuntimeError.invalidArgument("Unable to find parent tile for geometry")
}

/**

 A = earth radius
 
 public inverse(xy: XY): LonLat {
 return [
 (xy[0] * R2D) / A,
 (Math.PI * 0.5 - 2.0 * Math.atan(Math.exp(-xy[1] / A))) * R2D,
 ];
 }
 
 public forward(ll: LonLat): XY {
 const xy: LonLat = [
 A * ll[0] * D2R,
 A * Math.log(Math.tan(Math.PI * 0.25 + 0.5 * ll[1] * D2R)),
 ];
 // if xy value is beyond maxextent (e.g. poles), return maxextent.
 xy[0] > MAXEXTENT && (xy[0] = MAXEXTENT);
 xy[0] < -MAXEXTENT && (xy[0] = -MAXEXTENT);
 xy[1] > MAXEXTENT && (xy[1] = MAXEXTENT);
 xy[1] < -MAXEXTENT && (xy[1] = -MAXEXTENT);
 return xy;
 }
 
 
 */

let D2R = Double.pi / 180.0

func epsg4326ToWebMercator(point: Point) -> Point {
  /** Get the spherical mercator xy coordinates for a lon/lat point */
  let x = point.x * D2R * earthRadius
  let y = earthRadius * log(tan(Double.pi / 4 + point.y * D2R / 2))
  return Point(x: x, y: y)
}

func webMercatorToEpsg4326(point: Point) -> Point {
  /** Get the lon/lat coordinates for a spherical mercator xy point */
  let lon = point.x / (D2R * earthRadius)
  let lat = (Double.pi / 2 - 2 * atan(exp(-point.y / earthRadius))) / D2R
  return Point(x: lon, y: lat)
}
