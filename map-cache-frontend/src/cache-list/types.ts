import type { GeoJSON } from "geojson";

export enum MapCachePriority {
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

export interface MapCacheListing {
  id: number;
  sizes?: ResourceInfo;
  description: RockdCacheMetadata;
  definition: {
    geometry: GeoJSON.Geometry;
  };
  offlineStatus?: OfflineRegionStatus;
}

export interface CacheSystemInfo {
  caches: MapCacheListing[];
  sizes: ResourceInfo;
  totalSize: number;
}

export interface CacheRegionData {
  id: string;
  isGlobal: boolean | null;
  description: {
    name: string;
    created: string;
    updated: string;
    styleVersion: string;
    layers: string[];
  };
  definition: {
    style_url: string;
    pixel_ratio: number;
    glyphs_rasterization: boolean;
    min_zoom: number;
    max_zoom: number;
    geometry: Polygon;
  };
}
