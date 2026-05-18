//
//  PersistAssets.swift
//  MapCacheKit
//
//  Created by Daven Quinn on 8/21/25.
//
import Fluent
import FluentSQLiteDriver
import Vapor

let logger = Logger(label: "org.macrostrat.MapCacheKit")

func persistTile(
  to db: any SQLDatabase, urlTemplate: String,  tile: TileIndex, data: Data?, regionID: Int, pixelRatio: Int = 1
) async throws {
  try Task.checkCancellation() // Check if the task has been cancelled
  // Cast to SQLDatabase

  // Vector tiles get a pixel ratio of 1
  var ratio = 1
  if urlTemplate.contains("{ratio}") {
    // If the tile URL template contains a pixel ratio, we can use that
    ratio = pixelRatio
  }

  var data1: ByteBuffer? = nil
  if let data {
    // Convert Data to ByteBuffer
    data1 = ByteBuffer(data: data)
  }

  //TODO: add unique constraints

  let compressed = compressionAlgorithm(for: data) != nil
  
  logger.debug("Persisting tile at z:\(tile.z) x:\(tile.x) y:\(tile.y), (pixel ratio \(ratio), compressed: \(compressed))")

  let tileInsert: SQLQueryString = """
    INSERT INTO tiles (x, y, z, url_template, pixel_ratio, data, compressed, accessed)
    VALUES (
      \(bind: tile.x),
      \(bind: tile.y),
      \(bind: tile.z),
      \(bind: urlTemplate),
      \(bind: ratio),
      \(bind: data1),
      \(bind: compressed ? 1 : 0),
      \(bind: Date().timeIntervalSince1970)
    )
    ON CONFLICT (x, y, z, url_template, pixel_ratio) DO UPDATE SET
      data = excluded.data,
      compressed = excluded.compressed,
      accessed = excluded.accessed
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
  to db: any SQLDatabase, url: String, data: Data, kind: ResourceKind, regionID: Int
) async throws {
  let compressed = compressionAlgorithm(for: data) != nil
  let data1 = ByteBuffer(data: data)

  logger.debug("Persisting resource at url: \(url) (kind: \(kind), compressed: \(compressed))")
  let resourceInsert: SQLQueryString = """
    INSERT INTO resources (url, data, compressed, kind, accessed)
    VALUES (
      \(bind: url),
      \(bind: data1),
      \(bind: compressed ? 1 : 0),
      \(bind: kind.rawValue),
      \(bind: Date().timeIntervalSince1970)
    )
    ON CONFLICT (url) DO UPDATE SET
      data = excluded.data,
      compressed = excluded.compressed,
      kind = excluded.kind,
      accessed = excluded.accessed
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
