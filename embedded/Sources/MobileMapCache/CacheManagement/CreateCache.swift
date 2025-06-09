//
//  CreateCache.swift
//  MobileMapCache
//
//  Created by Daven Quinn on 5/19/25.
//

import GEOSwift
import SwiftTileMatrix

func getParentTile(for geom: Geometry) throws -> TileIndex {
  // Geometry is assumed to be in EPSG:4326
  let env = try geom.envelope()
 
  return TileIndex(x: 0, y: 0, z: 0)
}

