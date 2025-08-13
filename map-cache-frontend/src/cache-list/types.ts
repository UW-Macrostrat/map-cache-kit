import type { GeoJSON } from "geojson";

export enum MapCachePriority {
  Cache = "cache",
  Network = "network",
  CacheThenNetwork = "cache-then-network",
}

export enum MapCacheLayer {
  Basic = "basic",
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

export type RockdCacheCreationData = CacheCreationData<RockdCacheMetadata>;

export interface ResourceInfo {
  tile_count: number;
  tile_size: number;
  resource_count: number;
  resource_size: number;
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

export interface MapCacheListing {
  id: number;
  global: boolean;
  description: RockdCacheMetadata;
  definition: {
    geometry: GeoJSON.Geometry;
  };
  assets?: ResourceInfo;
  offlineStatus?: OfflineRegionStatus;
}

export interface CacheData {
  regions: MapCacheListing[];
  assets: ResourceInfo;
}
