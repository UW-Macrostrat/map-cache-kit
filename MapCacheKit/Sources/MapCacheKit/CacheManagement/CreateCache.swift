//
//  CreateCache.swift
//  MapCacheKit
//
//  Created by Daven Quinn on 5/19/25.
//

import Fluent
import FluentSQLiteDriver
import GEOSwift
import SwiftTileMatrix
import Vapor

enum StyleDefinition: Codable {
  case jsonData(JSON)
  case styleURL(String)

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let json = try? container.decode(JSON.self) {
      self = .jsonData(json)
    } else if let url = try? container.decode(String.self) {
      self = .styleURL(url)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Invalid style definition")
    }
  }
}

struct CacheRegionDefinition: Codable {
  let styles: [StyleDefinition]
  var minZoom: Int
  var maxZoom: Int
  var pixelRatio: Int
  var glyphsRasterization: Int
  var geometry: Polygon


  enum CodingKeys: String, CodingKey {
    case styles
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
  case downloadFailed(String)
  case configurationError(String)
}

// map-cache://regions/{id}/thumbnail

struct RequestedAsset: Hashable, Equatable {
  let urlTemplate: String
  let type: AssetType
  
  var thirdParty: Bool {
    return !urlTemplate.hasPrefix("mapbox://")
  }
  
  func resource() throws -> RequestedResource {
    if case .resource(let kind) = self.type {
      return .init(urlTemplate: self.urlTemplate, kind: kind)
    }
    throw RuntimeError.invalidArgument("Failed to unwrap resource")
  }
  
  func tile() throws -> CandidateTile {
    if case .tile(let tile) = self.type {
      return .init(
        x: tile.x,
        y: tile.y,
        z: tile.z,
        urlTemplate: self.urlTemplate
      )
    }
    throw RuntimeError.invalidArgument("Failed to unwrap tile")
  }
}

struct RequestedResource: Hashable, Equatable {
  let urlTemplate: String
  let kind: ResourceKind

  var thirdParty: Bool {
    return !urlTemplate.hasPrefix("mapbox://")
  }
}

struct CandidateTile: Hashable, Equatable {
  let x: Int
  let y: Int
  let z: Int
  let urlTemplate: String

  var thirdParty: Bool {
    return !urlTemplate.hasPrefix("mapbox://")
  }
}

struct RegionTileInfo {
  let neededTiles: Set<CandidateTile>
  let tilesToDownload: Set<CandidateTile>
  let tilesAlreadyDownloaded: Set<Int>
  let totalSizeOfTilesDownloaded: Int64
}

struct RegionResourceInfo {
  let neededResources: Set<RequestedResource>
  let resourcesToDownload: Set<RequestedResource>
  let resourcesAlreadyDownloaded: Set<Int>
  let totalSizeOfResourcesDownloaded: Int64
}

struct RegionAssetsPrepareStatus {
  let tiles: RegionTileInfo
  let resources: RegionResourceInfo
}

enum DownloadStatus {
  case success(Int64)
  case failure(any Error)
}

struct DownloadResult {
  let uri: URI
  let request: RequestedAsset
  let result: DownloadStatus
}

enum CacheDownloadStatus: String, Codable {
  case pending = "pending"
  case complete = "complete"
  case cancelled = "cancelled"
}

struct CacheRegionProgress: Content {
  let regionID: Int
  let resourcesDownloaded: Int
  let resourcesInitiallyDownloaded: Int
  let resourcesFailed: Int
  let resourcesTotal: Int
  let resourcesDownloadedSize: Int64
  let tilesDownloaded: Int
  let tilesInitiallyDownloaded: Int
  let tilesTotal: Int
  let tilesFailed: Int
  let tilesDownloadedSize: Int64
  let isFinished: Bool
  let lastErrorMessage: String?
  let status: CacheDownloadStatus

  var progress: Double {
    let total = Double(resourcesTotal + tilesTotal)
    guard total > 0 else { return 1.0 }
    return Double(resourcesDownloaded + tilesDownloaded + resourcesFailed + tilesFailed) / total
  }
}

func downloadRegionAssets(
  with app: Application,
  using definition: CacheRegionDefinition,
  regionID: Int,
  options: ResourceFindOptions,
  onProgress: @escaping (CacheRegionProgress) async throws -> Void = { _ in }
) async throws -> CacheRegionProgress {

  // Get the assets to download
  let assets = try await getRegionAssets(with: app, using: definition, options: options)
  guard let mapboxToken = try app.config.mapboxAPIToken else {
    throw RuntimeError.configurationError("Mapbox API token is not configured")
  }

  guard let db = app.db as? any SQLDatabase else {
    throw RuntimeError.databaseError("Database is not an SQLDatabase")
  }

  for tile in assets.tiles.tilesAlreadyDownloaded {
    try await insertLink(db, regionID: regionID, tileID: tile)
  }
  for resource in assets.resources.resourcesAlreadyDownloaded {
    try await insertLink(db, regionID: regionID, resourceID: resource)
  }

  var downloadTasks: [@Sendable () async throws -> DownloadResult] = []
  downloadTasks += assets.resources.resourcesToDownload.map { resource in
    let uri = URI(string: resource.urlTemplate)
    let asset = RequestedAsset(urlTemplate: resource.urlTemplate, type: .resource(resource.kind))
    return {
      try Task.checkCancellation()
      do {
        var params = [String: String]()

        if !resource.thirdParty {
          params = ["access_token": mapboxToken]
        }
        

        let uri = buildDownloadURL(for: asset, params: params)

        let res = try await downloadFile(with: app, url: uri)
        app.logger.info("Resource \(uri): \(res.status)")

        guard res.status == .ok,
              let body = res.body,
              body.readableBytes > 0
        else {
          throw RuntimeError.invalidArgument("Failed to download file from \(uri)")
        }
        let data = Data(buffer: body)

        let compressed = compressionAlgorithm(for: data) != nil

        try await persistResource(
          to: db, url: resource.urlTemplate, data: data,
          compressed: compressed, kind: resource.kind, regionID: regionID
        )
        return DownloadResult(
          uri: uri, request: asset, result: .success(Int64(data.count))
        )

      } catch {
        return DownloadResult(
          uri: uri, request: asset, result: .failure(error)
        )
      }
    }
  }
  downloadTasks += assets.tiles.tilesToDownload.map { tile in
    var params: [String: String] = [:]
    if !tile.thirdParty {
      params = ["access_token": mapboxToken]
    }

    let tileIx = TileIndex(x: tile.x, y: tile.y, z: tile.z)
    
    let asset = RequestedAsset(
      urlTemplate: tile.urlTemplate,
      type: .tile(tileIx)
    )
    let uri = buildDownloadURL(for: asset, params: params)
    return {
      try Task.checkCancellation()
      do {
        let res = try await downloadFile(with: app, url: uri)
        app.logger.debug("Tile \(uri): \(res.status)")

        var data: Data? = nil
        switch res.status {
        case .noContent, .notFound:
          data = nil
        case .ok:
          if let body = res.body, body.readableBytes > 0 {
            data = Data(buffer: body)
          }
        default:
          throw RuntimeError.invalidArgument("Unexpected status code \(res.status) for \(uri)")
        }

        let compressed = compressionAlgorithm(for: data) != nil

        try await persistTile(
          to: db,
          tile: tile,
          data: data,
          // TODO: be more intelligent about compression
          compressed: compressed,
          regionID: regionID,
          pixelRatio: definition.pixelRatio
        )

        return DownloadResult(
          uri: uri, request: asset, result: .success(Int64(data?.count ?? 0))
        )
      } catch {
        app.logger.error("Failed to download \(uri): \(error)")
        return DownloadResult(
          uri: uri, request: asset, result: .failure(error)
        )
      }
    }
  }

  // Download tiles
  var downloadedTiles = 0
  var downloadedTilesSize: Int64 = 0
  var failedTiles = 0
  let totalTiles = assets.tiles.tilesToDownload.count
  // Download resources
  var downloadedResources = 0
  var downloadedResourcesSize: Int64 = 0
  var failedResources = 0
  let totalResources = assets.resources.resourcesToDownload.count

  let initialProgress = CacheRegionProgress(
    regionID: regionID,
    resourcesDownloaded: 0,
    resourcesInitiallyDownloaded: assets.resources.resourcesAlreadyDownloaded.count,
    resourcesFailed: 0,
    resourcesTotal: totalResources,
    resourcesDownloadedSize: 0,
    tilesDownloaded: 0,
    tilesInitiallyDownloaded: assets.tiles.tilesAlreadyDownloaded.count,
    tilesTotal: totalTiles,
    tilesFailed: 0,
    tilesDownloadedSize: 0,
    isFinished: false,
    lastErrorMessage: nil,
    status: .pending
  )

  try await onProgress(initialProgress)

  var lastVal = initialProgress

  return try await withThrowingTaskGroup(of: DownloadResult.self) { taskGroup in
    // Handle completed downloads
    for task in downloadTasks {
      taskGroup.addTask(operation: task)
    }

    for try await result in taskGroup {
      let errorMessage: String?
      var status: CacheDownloadStatus = .pending
      switch result.result {
      case .success(let dataSize):
        switch result.request.type {
        case .tile(_):
          downloadedTiles += 1
          downloadedTilesSize += dataSize
        case .resource(_):
          downloadedResources += 1
          downloadedResourcesSize += dataSize
        }
        errorMessage = nil
        status = .pending
      case .failure(let error):
        errorMessage = error.localizedDescription
        switch result.request.type {
        case .tile:
          failedTiles += 1
        case .resource:
          failedResources += 1
        }
        if error is CancellationError {
          status = .cancelled
        }
      }

      if taskGroup.isEmpty && status != .cancelled {
        status = .complete
      }
      let val  = CacheRegionProgress(
        regionID: regionID,
        resourcesDownloaded: downloadedResources,
        resourcesInitiallyDownloaded: assets.resources.resourcesAlreadyDownloaded.count,
        resourcesFailed: failedResources,
        resourcesTotal: totalResources,
        resourcesDownloadedSize: downloadedResourcesSize,
        tilesDownloaded: downloadedTiles,
        tilesInitiallyDownloaded: assets.tiles.tilesAlreadyDownloaded.count,
        tilesTotal: totalTiles,
        tilesFailed: failedTiles,
        tilesDownloadedSize: downloadedTilesSize,
        isFinished: taskGroup.isEmpty,
        lastErrorMessage: errorMessage,
        status: status
      )

      lastVal = val
      try await onProgress(val)

      if status == .cancelled {
        return val
      }
    }
    return lastVal
  }
}

func getAndCacheThumbnail(
  with app: Application,
  for region: MBXCacheRegion,
) async throws -> Data? {
  /**
   Download a cache thumbnail and persist it to the database, associated with a region.
   This ensures that a thumbnail will always be available.
  */
  if region.isGlobal {
    return nil
  }
  guard let db = app.db as? any SQLDatabase else {
    throw RuntimeError.databaseError("Database is not an SQLDatabase")
  }
  guard let regionID = region.id else {
    throw RuntimeError.invalidArgument("Region ID is required to download thumbnail")
  }
  let template = "map-cache://regions/\(regionID)/thumbnail"
  guard let url = URL(string: template) else {
    throw RuntimeError.invalidArgument("Invalid thumbnail URL: \(template)")
  }

  // try to get the resource from the cache
  let resource = try await getCachedResource(from: db, url: url)
  if let data = resource?.data {
    return data
  }

  // get the thumbnail from the web
  let thumbnailURL = try buildCacheRegionThumbnailURL(app: app, geometry: region.getGeometry().geometry)
  app.logger.info("Downloading thumbnail from \(thumbnailURL)")
  let res = try await downloadFile(with: app, url: thumbnailURL)
  guard res.status == .ok,
        let body = res.body,
        body.readableBytes > 0
  else {
    throw RuntimeError.invalidArgument("Failed to download file from \(thumbnailURL)")
  }
  let data = Data(buffer: body)

  if compressionAlgorithm(for: data) != nil {
    throw RuntimeError.invalidArgument(
      "Thumbnail data should not be compressed, but it is. This is unexpected behavior.")
  }
  if getImageMimeType(data) == nil {
    throw RuntimeError.invalidArgument("Downloaded thumbnail data is not a valid image")
  }

  try await persistResource(
    to: db,
    url: template,
    data: data,
    compressed: false,
    kind: .thumbnail,
    regionID: regionID
  )
  return data
}

func compressionAlgorithm(for data: Data?) -> String? {
  // Check for magic bytes for deflate compression
  // NOTE: we may want to support other compression types in the future
  guard let data = data else {
    return nil
  }

  if data.starts(with: [0x78, 0x9C]) {
    return "deflate"
  }
  if data.starts(with: [0x1F, 0x8B]) {
    return "gzip"
  }
  // zstd
  if data.starts(with: [0x28, 0xb5, 0x2f, 0xfd]) {
    return "zstd"
  }
  return nil
}

func getRegionAssets(
  with app: Application, using definition: CacheRegionDefinition, options: ResourceFindOptions
) async throws -> RegionAssetsPrepareStatus {
  let tiles = try await getTilesToDownload(with: app, using: definition)

  // Get the resources to download
  let resources = try await getResourcesToDownload(with: app, using: definition, options: options)
  app.logger
    .info("""
          Assets to download:
          - \(resources.resourcesToDownload.count) resources
          - \(tiles.tilesToDownload.count) tiles
          """
    )
  return RegionAssetsPrepareStatus(tiles: tiles, resources: resources)
}

func getTilesToDownload(with app: Application, using definition: CacheRegionDefinition) async throws
  -> RegionTileInfo
{
  // Convert the geometry to a GEOSwift Polygon
  let polygon = definition.geometry

  // Get the intersecting tiles
  let tiles = try getIntersectingTiles(
    for: polygon.geometry, minZoom: definition.minZoom, maxZoom: definition.maxZoom)

  // Get the tile URL templates from the style definition
  var tileLayerDefs: Set<CacheLayerDefinition> = []
  for style in definition.styles {
    // Get the tile layers from the style
    let defs = try await getCacheableTileLayersFromStyle(with: app, style: style)
    tileLayerDefs.formUnion(defs)
  }

  // Get all tiles that may need to be downloaded
  var candidateTiles: Set<CandidateTile> = []

  for tile in tiles {
    for lyr in tileLayerDefs {
      // Special case for raster and raster-dem tiles (mapbox): no zoom 0 tiles for these types
      if (lyr.type == .raster || lyr.type == .rasterDem) && tile.z == 0 {
        continue
      }
      // Add the candidate tile
      candidateTiles.insert(
        CandidateTile(x: tile.x, y: tile.y, z: tile.z, urlTemplate: lyr.urlTemplate))
    }
  }

  guard let db = app.db as? any SQLDatabase else {
    throw RuntimeError.databaseError("Database is not an SQLDatabase")
  }

  var tilesToDownload: Set<CandidateTile> = []
  var tilesAlreadyDownloaded: Set<Int> = []
  var totalSizeOfTilesDownloaded: Int64 = 0

  // already downloaded tiles
  // need to get ID of tiles...
  for candidate in candidateTiles {
    let sql: SQLQueryString = """
      SELECT
        id,
        coalesce(length(data), 0) size
      FROM tiles
      WHERE x = \(bind: candidate.x)
        AND y = \(bind: candidate.y)
        AND z = \(bind: candidate.z)
        AND url_template = \(bind: candidate.urlTemplate)
      LIMIT 1
      """
    if let tile = try await db.raw(sql).first(decoding: ExistingAssetInfo.self) {
      totalSizeOfTilesDownloaded += tile.size
      tilesAlreadyDownloaded.insert(tile.id)
    } else {
      // If the tile is not in the database, we need to download it
      tilesToDownload.insert(candidate)
    }
  }

  return RegionTileInfo(
    neededTiles: candidateTiles,
    tilesToDownload: tilesToDownload,
    tilesAlreadyDownloaded: tilesAlreadyDownloaded,
    totalSizeOfTilesDownloaded: totalSizeOfTilesDownloaded
  )
}

struct ExistingAssetInfo: Content {
  let size: Int64
  let id: Int
}

func getResourcesToDownload(
  with app: Application, using definition: CacheRegionDefinition, options: ResourceFindOptions
) async throws -> RegionResourceInfo {
  var resources: Set<RequestedResource> = []

  for style in definition.styles {
    // Get the cacheable resources from the style
    let jsonData = try await getJSONForStyle(with: app, style: style)
    // Encode to data
    let data = try JSONEncoder().encode(jsonData)
    // decode the style
    let styleSpec = try JSONDecoder().decode(StyleSpec.self, from: data)

    // Could limit the maximum code point here...
    let r1 = try findResourcesRequestedByMapboxStyle(
      spec: styleSpec,
      options: options
    )

    resources.formUnion(r1)
  }

  // Check which resources are already downloaded
  var resourcesToDownload: Set<RequestedResource> = []
  var resourcesAlreadyDownloaded: Set<Int> = []
  var totalSizeOfResourcesDownloaded: Int64 = 0

  for resource in resources {
    // Check if the resource is already in the database
    if let resource = try await findResourceInDatabase(
      db: app.db, url: resource.urlTemplate, kind: resource.kind)
    {
      // Resource already exists
      totalSizeOfResourcesDownloaded += resource.size
      resourcesAlreadyDownloaded.insert(resource.id)
    } else {
      // Resource needs to be downloaded
      resourcesToDownload.insert(resource)
    }
  }

  return RegionResourceInfo(
    neededResources: resources,
    resourcesToDownload: resourcesToDownload,
    resourcesAlreadyDownloaded: resourcesAlreadyDownloaded,
    totalSizeOfResourcesDownloaded: totalSizeOfResourcesDownloaded
  )
}

func findResourceInDatabase(
  db: any Database, url: String, kind: ResourceKind
) async throws -> ExistingAssetInfo? {
  let sql: SQLQueryString = """
    SELECT
      id,
      length(data) as size
    FROM resources
    WHERE url = \(bind: url)
      AND kind = \(bind: kind.rawValue)
    LIMIT 1
    """

  guard let db = db as? any SQLDatabase else {
    throw RuntimeError.databaseError("Database is not an SQLDatabase")
  }

  if let row = try await db.raw(sql).first(decoding: ExistingAssetInfo.self) {
    return row
  }
  return nil
}

func getJSONForStyle(
  with app: Application,
  style: StyleDefinition
) async throws -> JSON {
  switch style {
  case .jsonData(let json):
    return json
  case .styleURL(let url):
    // Fetch the JSON from the URL
    let client = try await app.client.get(URI(string: url))
    guard client.status == .ok, let body = client.body else {
      throw RuntimeError.invalidArgument("Failed to fetch style JSON from URL: \(url)")
    }

    guard let data = body.getData(at: 0, length: body.readableBytes) else {
      throw RuntimeError.invalidArgument("Failed to convert response body to Data")
    }

    return try JSONDecoder().decode(JSON.self, from: data) // validate JSON
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

struct CacheLayerDefinition: Hashable, Equatable {
  let type: SourceType
  // Cache key used to store tiles in the database
  let urlTemplate: String
}

func getCacheableTileLayersFromStyle(
  with app: Application,
  style: StyleDefinition
) async throws -> Set<CacheLayerDefinition> {
  var defs: Set<CacheLayerDefinition> = []

  let data = try await getJSONForStyle(with: app, style: style)

  // Parse the JSON to extract tile URL templates
  let d1 = try JSONEncoder().encode(data)

  if let jsonObject = try? JSONSerialization.jsonObject(with: d1, options: [])
    as? [String: Any],
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
        defs.insert(CacheLayerDefinition(type: sourceType, urlTemplate: tiles[0]))
      } else if let urlTemplate = sourceDict["url"] as? String {
        // We are working with a tilejson file and need to infer the tile URL templates
        // We could do this by fetching and parsing the tileJSON also, but tileJSONs passed by mapbox
        // don't pass the correct requests anyway
        let url: String = try inferTileURLTemplate(
          from: urlTemplate, sourceType: sourceType
        )
        defs.insert(CacheLayerDefinition(type: sourceType, urlTemplate: url))
      }
    }
  }

  return defs
}

func inferTileURLTemplate(from tileJSONURL: String, sourceType: SourceType) throws -> String {
  if !tileJSONURL.starts(with: "mapbox://") {
    throw RuntimeError.invalidArgument(
      "Inferring tile URLs from non-Mapbox TileJSONs is not supported at the moment")
  }

  switch sourceType {
  case .vector:
    return tileJSONURL.replacingOccurrences(of: "mapbox://", with: "mapbox://tiles/")
      + "/{z}/{x}/{y}.vector.pbf"
  case .raster:
    return tileJSONURL.replacingOccurrences(of: "mapbox://", with: "mapbox://tiles/")
      + "/{z}/{x}/{y}{ratio}.png"
  case .rasterDem:
    // Raster DEMs do not support ratios
    return tileJSONURL.replacingOccurrences(of: "mapbox://", with: "mapbox://tiles/")
      + "/{z}/{x}/{y}.png"
  default:
    throw RuntimeError.invalidArgument(
      "\(sourceType) sources are not supported for tileJSON inference")
  }
}

func persistTile(
  to db: any SQLDatabase, tile: CandidateTile, data: Data?, compressed: Bool, regionID: Int, pixelRatio: Int = 1
) async throws {
  try Task.checkCancellation() // Check if the task has been cancelled
  // Cast to SQLDatabase

  // Vector tiles get a pixel ratio of 1
  var ratio = 1
  if tile.urlTemplate.contains("{ratio}") {
    // If the tile URL template contains a pixel ratio, we can use that
    ratio = pixelRatio
  }

  var data1: ByteBuffer? = nil
  if let data {
    // Convert Data to ByteBuffer
    data1 = ByteBuffer(data: data)
  }

  //TODO: add unique constraints


  let tileInsert: SQLQueryString = """
    INSERT INTO tiles (x, y, z, url_template, pixel_ratio, data, compressed, accessed)
    VALUES (
      \(bind: tile.x),
      \(bind: tile.y),
      \(bind: tile.z),
      \(bind: tile.urlTemplate),
      \(bind: ratio),
      \(bind: data1),
      \(bind: compressed ? 1 : 0),
      \(bind: Date().timeIntervalSince1970)
    )
    RETURNING id
  """

  guard let id = try await db.raw(tileInsert)
    .first(decodingColumn: "id", as: Int.self)
          else {
    throw RuntimeError.databaseError("Failed to insert or update tile")
  }

  try await insertLink(db, regionID: regionID, tileID: id)
}

func persistResource(
  to db: any SQLDatabase, url: String, data: Data, compressed: Bool, kind: ResourceKind, regionID: Int
) async throws {
  let data1 = ByteBuffer(data: data)

  let resourceInsert: SQLQueryString = """
    INSERT INTO resources (url, data, compressed, kind, accessed)
    VALUES (
      \(bind: url),
      \(bind: data1),
      \(bind: compressed ? 1 : 0),
      \(bind: kind.rawValue),
      \(bind: Date().timeIntervalSince1970)
    )
    RETURNING id
  """

  guard let id = try await db.raw(resourceInsert)
    .first(decodingColumn: "id", as: Int.self)
          else {
    throw RuntimeError.databaseError("Failed to insert resource into database")
  }
  // Now insert into region_resources
  try await insertLink(db, regionID: regionID, resourceID: id)
}

func insertLink(_ db: any SQLDatabase, regionID: Int, resourceID: Int) async throws {
  let regionResourceInsert: SQLQueryString = """
    INSERT INTO region_resources (region_id, resource_id)
    VALUES (\(bind: regionID), \(bind: resourceID))
    ON CONFLICT (region_id, resource_id) DO NOTHING
  """
  _ = try await db.raw(regionResourceInsert).run()
}

func insertLink(_ db: any SQLDatabase, regionID: Int, tileID: Int) async throws {
  let regionResourceInsert: SQLQueryString = """
    INSERT INTO region_tiles (region_id, tile_id)
    VALUES (\(bind: regionID), \(bind: tileID))
    ON CONFLICT (region_id, tile_id) DO NOTHING
  """
  _ = try await db.raw(regionResourceInsert).run()
}


extension TileCoord {
  var envelopeGeographic: Envelope {
    let env = self.envelope
    let min = webMercatorToEpsg4326(point: env.minXMinY)
    let max = webMercatorToEpsg4326(point: env.maxXMaxY)
    return Envelope(minX: min.x, maxX: max.x, minY: min.y, maxY: max.y)
  }
}

func getIntersectingTiles(for geom: Geometry, minZoom: Int, maxZoom: Int) throws -> Set<TileCoord> {
  let parentTile = try getParentTile(for: geom)

  if minZoom < 0 {
    throw RuntimeError.invalidArgument("Minimum zoom level must be greater than or equal to 0")
  }

  var tiles: [TileCoord] = []
  // Prevents us from having to calculate intersections for all tiles
  var parentTiles: [TileCoord] = [parentTile]
  var currentLevelTiles: [TileCoord] = []

  for zoom in stride(from: min(minZoom, parentTile.z), through: maxZoom, by: 1) {
    let deltaZ = zoom - parentTile.z
    let factor = Double.pow(2, deltaZ)
    let xTile = Int(Double(parentTile.x) * factor)
    let yTile = Int(Double(parentTile.y) * factor)

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
            if try geom.intersects(newTile.envelopeGeographic) {
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
  let t1 = tiles.filter { $0.z >= minZoom }
  return Set(t1)
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
  let tileCoord = TileCoord(0, 0, 0)

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

  return try getParentTile(for: webMercatorEnvelope, within: tileCoord, maxZoom: 30)

}

func getParentTile(for envelope: Envelope, within tileCoord: TileCoord, maxZoom: Int = 30) throws -> TileCoord {
  if tileCoord.z >= maxZoom {
    return tileCoord
  }

  // Check if any of the child tiles cover the geometry
  let x0 = tileCoord.x * 2
  let y0 = tileCoord.y * 2
  let z = tileCoord.z + 1
  let childTiles = [
    TileCoord(x0, y0, z),  // Bottom-left
    TileCoord(x0 + 1, y0, z),  // Bottom-right
    TileCoord(x0, y0 + 1, z),  // Top-left
    TileCoord(x0 + 1, y0 + 1, z),  // Top-right
  ]

  for childTile in childTiles {
    if try childTile.envelope.covers(envelope) {
      return try getParentTile(for: envelope, within: childTile, maxZoom: maxZoom)
    }
  }
  return tileCoord
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
