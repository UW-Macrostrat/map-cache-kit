//
//  DownloadURLCreation.swift
//  MapCacheKit
//
//  Created by Daven Quinn on 8/21/25.
//

import Vapor

func buildDownloadURL(for asset: RequestedAsset, params: [String: String?] = [:]) -> URI {
  switch asset.type {
  case .tile(let tile):
    return buildDownloadURL(urlTemplate: asset.urlTemplate, tile: tile, params: params)
  case .resource(let kind):
    return buildDownloadURL(urlTemplate: asset.urlTemplate, resourceKind: kind, params: params)
  }
}

fileprivate func buildDownloadURL(urlTemplate: String, tile: TileIndex, params: [String: String?] = [:]) -> URI {
  var tileURL = urlTemplate
    .replacingOccurrences(of: "{z}", with: "\(tile.z)")
    .replacingOccurrences(of: "{x}", with: "\(tile.x)")
    .replacingOccurrences(of: "{y}", with: "\(tile.y)")
    .replacingOccurrences(of: "{ratio}", with: "@2x")
    .replacingOccurrences(of: "mapbox://tiles", with: "https://api.mapbox.com/v4")
  
  // Replace webp
  if tileURL.hasSuffix(".webp") {
    tileURL = tileURL.replacingOccurrences(of: ".webp", with: ".png")
  }
  
  var uri = URI(string: tileURL)
  uri.query = buildParams(params)
  return uri
}


fileprivate func buildDownloadURL(urlTemplate: String, resourceKind: ResourceKind, params: [String: String?] = [:]) -> URI {
  var resourceURL = urlTemplate
  if resourceURL.hasPrefix("mapbox://fonts/") {
    resourceURL = resourceURL.replacingOccurrences(of: "mapbox://fonts/", with: "https://api.mapbox.com/fonts/v1/")
  } else if resourceURL.hasPrefix("mapbox://sprites/") {
    resourceURL = resourceURL.replacingOccurrences(of: "mapbox://sprites/", with: "https://api.mapbox.com/styles/v1/")
    resourceURL = addSpriteSuffix(url: resourceURL)
  } else if resourceURL.hasPrefix("mapbox://styles/") {
    resourceURL = resourceURL.replacingOccurrences(of: "mapbox://styles/", with: "https://api.mapbox.com/styles/v1/")
  } else if resourceURL.hasPrefix("mapbox://tiles/") {
    resourceURL = resourceURL.replacingOccurrences(of: "mapbox://tiles/", with: "https://api.mapbox.com/v4/")
  } else if resourceURL.hasPrefix("mapbox://") {
    // A tileset
    resourceURL = resourceURL.replacingOccurrences(of: "mapbox://", with: "https://api.mapbox.com/v4/")
    resourceURL += ".json"
  }
  
  
  var uri = URI(string: resourceURL)
  // Encode URL parameters if provided
  uri.query = buildParams(params)
  return uri
}
