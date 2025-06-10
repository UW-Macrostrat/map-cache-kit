import type { GeoJSON } from "geojson";

enum MapCachePriority {
  Cache = "cache",
  Network = "network",
  CacheThenNetwork = "cache-then-network",
}

enum MapCacheLayer {
  Basemap = "basemap",
  Satellite = "satellite",
  Bedrock = "bedrock",
}

export interface CacheCreationData<Metadata extends object = {}> {
  minZoom: number;
  maxZoom: number;
  geometry: GeoJSON.Geometry;
  styleURL: string;
  metadata: Metadata;
}

export interface RockdCacheMetadata {
  name: string;
  created: string;
  updated: string;
  layers: MapCacheLayer[];
  styleVersion: string;
}

export interface ResourceInfo {
  tileCount: number;
  tileSize: number;
  resourceCount: number;
  resourceSize: number;
}

/* This struct comes from Mapbox's internal config */
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

interface MapCacheListing {
  id: number;
  geometry: GeoJSON.Geometry;
  sizes?: ResourceInfo;
  metadata: RockdCacheMetadata;
  offlineStatus?: OfflineRegionStatus;
}

export interface CacheSystemInfo {
  caches: MapCacheListing[];
  sizes: ResourceInfo;
  totalSize: number;
}
