//
//  DownloadQueue.swift
//  MapCacheKit
//
//  Created by Daven Quinn on 8/17/25.
//
// https://losingfight.com/blog/2024/04/14/swift-asyncawait-do-you-even-need-a-queue/
import Vapor

func downloadFile(with app: Application, url: URI) async throws -> ClientResponse {
  let timeout = try app.config.httpRequestTimeout
  let jitter = Double(timeout.nanoseconds) * Double.random(in: 0.25...1.0)
  try await Task.sleep(nanoseconds: UInt64(jitter))
  try Task.checkCancellation()
  
  app.logger.debug("Downloading \(url)")
  do {
    return try await app.client.get(url)
  } catch {
    app.logger.error("Failed to download \(url): \(error)")
    throw error
  }
}

