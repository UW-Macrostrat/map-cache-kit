//
//  CacheRegionsController.swift
//  MobileMapCache
//
//  Created by Daven Quinn on 5/17/25.
//

import Fluent
import Vapor
import FluentSQL

struct CacheRegionsController: RouteCollection {
  func boot(routes: any RoutesBuilder) throws {
    let regions = routes.grouped("regions")
    
    regions.get(use: self.index)
  }
  
  @Sendable
  func index(req: Request) async throws -> [String] {
    // Get a list of regions
    let sql: SQLQueryString = """
      SELECT definition FROM regions
      """
    
    guard let db = req.db as? any SQLDatabase else {
      throw Abort(.internalServerError, reason: "Database is not SQLDatabase")
    }
    
    // Description is a JSON string
    let regions = try await db.raw(sql)
      .all(decodingColumn: "definition", as: String.self)
    return regions
  }
}
