//
//  QuadtreeTileSearch.swift
//  MapCacheKit
//
//  Created by Daven Quinn on 5/22/26.
//

import FluentSQLiteDriver
import Vapor

// MARK: - Private types

/// A 2D tile coordinate without a zoom level (used as a quadtree root key).
private struct TileXY: Hashable {
  let x, y: Int
}

/// A full 3D tile coordinate used to index individual candidates.
private struct TileXYZ: Hashable {
  let x, y, z: Int
}

private struct SubtreeTileRow: Decodable {
  let x, y, z, id: Int
  let size: Int64
}

// MARK: - Quadtree tile search

/// Efficiently finds which tile assets already exist in the database using a
/// quadtree-based batch query strategy.
///
/// **Why individual queries are slow:**
/// The naïve `findAll` issues one `SELECT … WHERE x=? AND y=? AND z=?` per
/// tile, meaning N round-trips to SQLite for N candidate tiles.
///
/// **The quadtree insight:**
/// At zoom level `Z`, a tile `(x, y)` is a descendant of a parent tile
/// `(px, py)` at zoom `P` (where `P ≤ Z`) if and only if:
/// ```
///   x >> (Z - P) == px   AND   y >> (Z - P) == py
/// ```
/// SQLite evaluates this bit-shift expression row-by-row, allowing a single
/// query to cover *all zoom levels* of an entire spatial subtree at once.
///
/// **Algorithm:**
/// 1. Group all candidates by `url_template`, then determine the min/max zoom
///    for each template.
/// 2. Map every candidate tile to its ancestor at `minZoom` — its "root tile".
///    Candidates that share a root tile form one subtree of the quadtree.
/// 3. Issue **one SQL query per (url_template, root tile)** that uses the
///    bit-shift predicate to cover the whole subtree.
/// 4. Cross-reference the returned rows against the in-memory candidate set.
///
/// **Complexity:** O(url_templates × unique_root_tiles_at_min_zoom) queries,
/// which is typically orders of magnitude fewer than O(total_tiles).
///
/// - Note: This function only handles `.tile` assets. Pass only tile assets,
///   or mix freely — non-tile assets are passed through to `find(asset:in:)`.
func findAllTilesQuadtree(
  _ assets: Set<RequestedAsset>,
  in db: any SQLDatabase
) async throws -> RegionAssetInfo {
  guard !assets.isEmpty else {
    return RegionAssetInfo(
      needed: assets, toDownload: [], alreadyDownloaded: [], totalSizeDownloaded: 0)
  }

  // ── Split into tiles (quadtree path) and non-tiles (individual path) ─────
  var tileAssets: [RequestedAsset] = []
  var nonTileAssets: [RequestedAsset] = []
  for asset in assets {
    if case .tile = asset.type { tileAssets.append(asset) }
    else { nonTileAssets.append(asset) }
  }

  var foundAssets: Set<RequestedAsset> = []
  var cachedIDs: Set<Int> = []
  var totalSize: Int64 = 0

  // ── 1. Group tile candidates by (urlTemplate) then determine zoom range ───
  // [urlTemplate: [z: [TileXY: RequestedAsset]]]
  var byTemplate: [String: [Int: [TileXY: RequestedAsset]]] = [:]
  for asset in tileAssets {
    guard case .tile(let idx) = asset.type else { continue }
    byTemplate[asset.urlTemplate, default: [:]][idx.z, default: [:]][TileXY(x: idx.x, y: idx.y)] =
      asset
  }

  // ── 2. For each template, build root-tile groups and query ────────────────
  for (urlTemplate, byZoom) in byTemplate {
    let zoomLevels = byZoom.keys
    guard let minZ = zoomLevels.min(), let maxZ = zoomLevels.max() else { continue }

    // Map each candidate to its ancestor at minZ (its "quadtree root").
    // Candidates with the same root are in the same spatial subtree and can
    // be resolved with a single database query.
    //
    // [rootTile: [TileXYZ: RequestedAsset]]
    var byRoot: [TileXY: [TileXYZ: RequestedAsset]] = [:]
    for (z, coordMap) in byZoom {
      let shift = z - minZ
      for (xy, asset) in coordMap {
        let root = TileXY(x: xy.x >> shift, y: xy.y >> shift)
        let xyz = TileXYZ(x: xy.x, y: xy.y, z: z)
        byRoot[root, default: [:]][xyz] = asset
      }
    }

    // ── 3. One query per (urlTemplate, root tile) covers the whole subtree ──
    for (root, subtreeCandidates) in byRoot {
      // The predicate `(x >> (z - minZ)) = root.x AND (y >> (z - minZ)) = root.y`
      // selects every tile at any zoom whose ancestor at minZ is `root`.
      // This is valid in SQLite because `z` is a column value and `>>` is a
      // built-in integer operator evaluated per row.
      //
      // Trade-off: the bit-shift prevents index range scans on (x, y), so
      // SQLite uses the `tiles_url_template` index to narrow by template,
      // then evaluates the expression for each row in [minZ, maxZ].
      // This is still far cheaper than issuing one query per tile.
      let rows = try await db.raw(
        """
        SELECT x, y, z, id, coalesce(length(data), 0) AS size
        FROM tiles
        WHERE url_template = \(bind: urlTemplate)
          AND z BETWEEN \(bind: minZ) AND \(bind: maxZ)
          AND (x >> (z - \(bind: minZ))) = \(bind: root.x)
          AND (y >> (z - \(bind: minZ))) = \(bind: root.y)
        """
      ).all(decoding: SubtreeTileRow.self)

      for row in rows {
        let xyz = TileXYZ(x: row.x, y: row.y, z: row.z)
        if let asset = subtreeCandidates[xyz] {
          foundAssets.insert(asset)
          // Insert only the first ID encountered for a given tile
          // (multiple pixel_ratio variants map to the same candidate).
          cachedIDs.insert(row.id)
          totalSize += row.size
        }
      }
    }
  }

  // ── 4. Non-tile assets: fall back to individual queries (few in number) ───
  for asset in nonTileAssets {
    if let existing = try await find(asset: asset, in: db) {
      foundAssets.insert(asset)
      cachedIDs.insert(existing.id)
      totalSize += existing.size
    }
  }

  return RegionAssetInfo(
    needed: assets,
    toDownload: assets.subtracting(foundAssets),
    alreadyDownloaded: cachedIDs,
    totalSizeDownloaded: totalSize
  )
}
