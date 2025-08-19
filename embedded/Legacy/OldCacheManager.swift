//
//  MapCacheManager.swift
//  Rockd
//
//  Created by Daven Quinn on 4/24/22.
//  Copyright © 2022 Daven Quinn. All rights reserved.
//

import Foundation
import MapboxMaps
import Turf
import Combine
import GRDB
import Dispatch

func mapboxAccessToken()-> String {
  return Bundle.main.object(forInfoDictionaryKey: "MGLMapboxAccessToken") as! String
}

extension Formatter {
  static let iso8601 = ISO8601DateFormatter()
}

extension Date {
  var iso8601: String { return Formatter.iso8601.string(from: self) }
}

func documentDirectory() throws -> URL {
  let fileManager = FileManager.default
  let urls = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
  guard let documentDirectory: URL = urls.first else { throw RuntimeError.invalidValue("Filesystem error") }
  return documentDirectory
}

func createFolder(at url: URL) throws {
  // Create it if it doesn't exist
  if !FileManager.default.fileExists(atPath: url.path) {
    try FileManager.default.createDirectory(atPath: url.path, withIntermediateDirectories: false, attributes: nil)
  }
}

struct ResourceInfo: Codable {
  let tileCount: UInt64?
  let tileSize: UInt64?
  let resourceCount: UInt64?
  let resourceSize: UInt64?
}

struct ResourceRow: Decodable, FetchableRecord, Identifiable {
  let id: Int
  let resources: ResourceInfo
  
  enum CodingKeys: String, CodingKey {
    case id
  }
  
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = try container.decode(Int.self, forKey: .id)
    self.resources = try ResourceInfo(from: decoder)
  }
}

struct MapCacheListing: Encodable {
  let id: Int64
  let geometry: GeoJSONObject
  let metadata: JSONObject
  let sizes: ResourceInfo?
  let offlineStatus: OfflineRegionStatus?
}

struct CacheSystemInfo: Encodable {
  let caches: [MapCacheListing]
  let sizes: ResourceInfo
  let totalSize: UInt64
}

enum RuntimeError: Error {
  case invalidValue(String)
}

enum TilesetDownloadAction {
  case start, pause
}

func message(for error: Error)->String {
  switch error {
  case RuntimeError.invalidValue(let msg):
    return "Runtime error: \(msg)"
  default:
    return error.localizedDescription
  }
}

func databaseTransaction(_ fn: @escaping (Database)->Void) {
  do {
    guard let q = MapCacheManager.shared.database else {
      throw RuntimeError.invalidValue("Could not get database")
    }
    try q.read { fn($0) }
  } catch let err {
    print(err)
  }
}

let initialStatus = OfflineRegionStatus(
  downloadState: .active,
  completedResourceCount: 0,
  completedResourceSize: 0,
  completedTileCount: 0,
  requiredTileCount: 1,
  completedTileSize: 1,
  requiredResourceCount: 1,
  requiredResourceCountIsPrecise: false
)

@objc(CacheDownloadManager)
class CacheDownloadManager: NSObject {
  var regionsInProgress: [Int64: OfflineRegion] = [:]
  var onRegionStatus: ((Int64, OfflineRegionStatus)->Void)? = nil
  
  func startTilesetDownload(for region: OfflineRegion) {
    let id = region.getIdentifier()
    let observer = OfflineDownloadObserver { [weak self] (status) in
      print(status.downloadState)
      print("Downloaded \(status.completedResourceCount)/\(status.requiredResourceCount) resources; \(status.completedResourceSize) bytes downloaded.")
      let nComplete = Float(status.completedResourceCount)/Float(status.requiredResourceCount)
      print("Completed: \(nComplete)")
      if status.downloadState == .inactive {
        print("Done!")
        //self?.setupTileRegions()
        self?.regionsInProgress.removeValue(forKey: id)
      }
      self?.onRegionStatus?(id, status)
    }
    
    self.onRegionStatus?(id, initialStatus)
    
    region.setOfflineRegionObserverFor(observer)
    region.setOfflineRegionDownloadStateFor(.active)
    
    // must keep a strong reference to the region or it will get
    // deallocated and the observer will not be notified.
    self.regionsInProgress[id] = region
  }
  
  func cancelTilesetDownload(for region: OfflineRegion) {
    region.setOfflineRegionDownloadStateFor(.inactive)
    self.regionsInProgress.removeValue(forKey: region.getIdentifier())
  }
}

@available(*, deprecated, message: "This uses Mapbox-deprecated APIs, but we should be OK for a while...")
class MapCacheManager {
  static let shared = MapCacheManager()
  // Need to lock and unlock the cache
  var preflightLock = NSLock()
  var preflightCache: [TileResponse] = []
  
  
  let cacheDir: URL
  
  let encoder = JSONEncoder()
  let decoder = JSONDecoder()
  let regionManager: OfflineRegionManager
  let downloadManager: CacheDownloadManager
  
  let queue = DispatchQueue(label: "com.macrostrat.Rockd-tiles", qos: .userInteractive)
  
  // Database is lazily initialized
  var _database: DatabasePool? = nil
  var database: DatabasePool? {
    do {
      try setupDatabase()
    } catch let err {
      print(message(for: err))
    }
    return self._database
  }
  
  init() {
    /* We customize the cache location, at least for now, so we can have some visibility and
     control over it as part of the app development process. */
    let documentDir = try! documentDirectory()
    var cacheDir = documentDir.appendingPathComponent("Caches")
    
    // Create it if it doesn't exist
    try! createFolder(at: cacheDir)
    
    // exclude the cache dir from iCloud backup
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try! cacheDir.setResourceValues(values)
    
    self.cacheDir = cacheDir
    
    let opts = ResourceOptions(accessToken: mapboxAccessToken(), dataPathURL: cacheDir)
    
    self.regionManager = OfflineRegionManager(resourceOptions: opts)
    self.downloadManager = CacheDownloadManager()
    
    // Tile count limit should be configurable
    self.regionManager.setOfflineMapboxTileCountLimitForLimit(10000)
    
    do {
      try setupDatabase()
    } catch let err {
      print(message(for: err))
    }
  }
  
  func setupDatabase() throws {
    if self._database != nil { return }
    
    var cfg = Configuration()
    cfg.readonly = true
    
    let db = try DatabasePool(path: self.cacheDatabaseFile.path, configuration: cfg)
    self._database = db
  }
  
  var cacheDatabaseFile: URL {
    return self.cacheDir.appendingPathComponent("map_data.db")
  }
  
  var cacheDatabaseSize: UInt64 {
    let attr = try? FileManager.default.attributesOfItem(atPath: cacheDatabaseFile.path)
    return attr?[.size] as? UInt64 ?? UInt64(0)
  }
  
  func createOfflineRegion(for def: OfflineRegionGeometryDefinition, with meta: Data? = nil) async throws -> OfflineRegion {
    try self.setupDatabase()
    let region = try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.main.async {
        self.regionManager.createOfflineRegion(for: def) { res in
          continuation.resume(with: res)
        }
      }
    }
    
    guard let data = meta else {
      throw RuntimeError.invalidValue("Offline region metadata was nil.")
    }
    
    try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.main.async {
        region.setMetadata(data) { continuation.resume(with: $0) }
      }
    }
    
    return region
  }
  
  func createTileset(style: StyleURI, geometry: Turf.Geometry, zoomRange: ClosedRange<UInt8>, metadata: [String: Any] = [:]) async throws -> Int64 {
    let offlineRegionDef = await OfflineRegionGeometryDefinition(
      styleURL: style.rawValue,
      geometry: geometry,
      minZoom: Double(zoomRange.lowerBound),
      maxZoom: Double(zoomRange.upperBound),
      pixelRatio: Float(UIScreen.main.scale),
      // Changing .noGlyphsRasterizedLocally to .ideographsRasterizedLocally should result in a huge savings of cache space
      // Need to work on making styles smaller: https://docs.mapbox.com/help/troubleshooting/mobile-offline/
      glyphsRasterizationMode: .ideographsRasterizedLocally
    )
    
    let meta = try JSONSerialization.data(withJSONObject: metadata)
    
    let region = try await self.createOfflineRegion(for: offlineRegionDef, with: meta)
    return region.getIdentifier()
  }
  
  func manageTilesetDownload(for region: OfflineRegion, with action: TilesetDownloadAction = .start) {
    switch action {
    case .start:
      self.downloadManager.startTilesetDownload(for: region)
    case .pause:
      self.downloadManager.cancelTilesetDownload(for: region)
    }
  }
  
  func getRegion(for id: Int64, callback: @escaping (Result<OfflineRegion,Error>)->Void) {
    self.regionManager.offlineRegions { res in
      switch res {
      case .success(let regions):
        if let region = regions.first(where: { reg in
          return id == reg.getIdentifier()
        }) {
          callback(.success(region))
        } else {
          callback(.failure(RuntimeError.invalidValue("Could not find region for id \(id)")))
        }
      case .failure(let error):
        callback(.failure(error))
      }
    }
  }
  
  func purge(id: Int64, callback: @escaping (Result<Void,Error>)->Void) {
    DispatchQueue.main.async {
      self.getRegion(for: id) { res in
        switch res {
        case .success(let region):
          region.purge { r1 in
            callback(r1)
          }
        case .failure(let error):
          callback(.failure(error))
        }
      }
    }
  }
  
  func removeAllCaches() async throws {
    let regions = try await self.getAvailableCaches()
    for region in regions.caches {
      try await withCheckedThrowingContinuation { continuation in
        self.purge(id: region.id) { res in
          continuation.resume(with: res)
        }
      }
    }
  }
  
  func getOfflineStatus(for region: OfflineRegion) async throws -> OfflineRegionStatus {
    return try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.main.async {
        region.getStatus { res in
          continuation.resume(with: res)
        }
      }
    }
  }
  
  func getAvailableCaches() async throws -> CacheSystemInfo {
    let regions = try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.main.async {
        self.regionManager.offlineRegions { res in
          continuation.resume(with: res)
        }
      }
    }
    
    var resourceData = try getResourceData()
    
    var regionData: [MapCacheListing] = []
    for region in regions {
      let status = try await self.getOfflineStatus(for: region)
      let id = region.getIdentifier()
      
      var resources: ResourceInfo? = nil
      if let ix = resourceData.firstIndex(where: { $0.id == id }) {
        resources = resourceData.remove(at: ix).resources
      }
      let desc = try self.description(
        for: region,
        resources: resources,
        offlineStatus: status
      )
      regionData.append(desc)
    }
    
    guard
      let ix = resourceData.firstIndex(where: { $0.id == -1 })
    else {
      throw RuntimeError.invalidValue("Total resource counts not returned.")
    }
    let totalResources = resourceData[ix].resources
    
    return CacheSystemInfo(
      caches: regionData,
      sizes: totalResources,
      totalSize: cacheDatabaseSize
    )
  }
  
  func description(
    for region: OfflineRegion,
    resources: ResourceInfo?,
    offlineStatus: OfflineRegionStatus?
  ) throws -> MapCacheListing {
    let id = region.getIdentifier()
    
    //let meta = try JSONSerialization.jsonObject(with: region.getMetadata(), options: [])
    let meta = try? JSONDecoder().decode(JSONObject.self, from: region.getMetadata())
    
    guard let def = region.getGeometryDefinition(),
          let geometry = def.geometry
    else {
      throw RuntimeError.invalidValue("Cannot get geometry definition")
    }
    
    return MapCacheListing(
      id: id,
      geometry: geometry.geoJSONObject,
      metadata: meta ?? [:],
      sizes: resources,
      offlineStatus: offlineStatus
    )
  }
  
  func getResourceData() throws -> [ResourceRow] {
    guard let q = self.database else {
      throw RuntimeError.invalidValue("Database not found")
    }
    
    return try q.read { db throws -> [ResourceRow] in
      return try ResourceRow.fetchAll(db, sql: regionResourcesQuery)
    }
  }
  
let preflightCacheQueue = DispatchQueue(label: "preflight-cache", attributes: .concurrent)



let getResource = """
SELECT
  data,
  url,
  kind,
  compressed
FROM resources
WHERE url = :path
LIMIT 1
"""

let regionResourcesQuery = """
WITH res AS (
SELECT
 region_id,
 sum(length(r.data)) resource_size,
 count(r.data) resource_count
FROM region_resources rr
JOIN resources r
  ON rr.resource_id = r.id
GROUP BY rr.region_id
), til AS (
SELECT
 region_id,
 sum(length(t.data)) tile_size,
 count(t.data) tile_count
FROM region_tiles rt
JOIN tiles t
  ON rt.tile_id = t.id
GROUP BY rt.region_id
)
SELECT
 t.region_id id,
 t.tile_count tileCount,
 t.tile_size tileSize,
 r.resource_count resourceCount,
 r.resource_size resourceSize
FROM til t
JOIN res r
  ON t.region_id = r.region_id
UNION ALL
SELECT
  -1,
  (SELECT count(*) FROM tiles),
  (SELECT sum(length(data)) FROM tiles),
  (SELECT count(*) FROM resources),
  (SELECT sum(length(data)) FROM resources);
"""
// can easily add a where clause: WHERE t.region_id = 31


/* MARK: Download observer */

let rockdDownloadQueue = DispatchQueue(label: "com.macrostrat.Rockd-downloads", qos: .userInteractive)

@available(*, deprecated, message: "This uses Mapbox-deprecated APIs, but we should be OK for a while...")
final class OfflineDownloadObserver: OfflineRegionObserver {
  
  private let onChange: (OfflineRegionStatus) -> Void
  @Published private(set) var status: OfflineRegionStatus? = nil
  var subscriptions = Set<AnyCancellable>()
  
  init(statusChanged: @escaping (OfflineRegionStatus) -> Void) {
    self.onChange = statusChanged
    // Only call back to UI every 200 ms
    let debouncedPublisher = self.$status.throttle(for: 0.05, scheduler: rockdDownloadQueue, latest: true)
    debouncedPublisher.sink(receiveValue: { val in
      guard let status = val else { return }
      self.onChange(status)
    }).store(in: &subscriptions)
  }
  
  func statusChanged(for status: OfflineRegionStatus) {
    self.status = status
  }
  
  func responseError(forError error: ResponseError) {
    // Some errors are considered recoverable and will be retried
    print("Offline resource download error: \(error.reason), \(error.message)")
  }
  
  func mapboxTileCountLimitExceeded(forLimit limit: UInt64) {
    print("Mapbox tile count max (\(limit)) has been exceeded!")
  }
}
