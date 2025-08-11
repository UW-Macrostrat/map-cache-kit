import type { MapCacheListing } from "./types";
import { LngLatBounds } from "mapbox-gl";
import { bbox } from "@turf/bbox";
import { bboxPolygon } from "@turf/bbox-polygon";
import type { BBox, Polygon } from "geojson";

export const GLOBAL_CACHE_NAME = "Global cache";
export const GLOBAL_EXTENT = new LngLatBounds([-180, -90], [180, 90]);

export function isGlobalCache(cache: MapCacheListing): boolean {
  return cache.description.name == GLOBAL_CACHE_NAME;
}

export function isStyleCache(cache: MapCacheListing): boolean {
  return cache.description.name.startsWith("rockd-cache.v");
}

export function findGlobalCache(
  caches: MapCacheListing[],
): MapCacheListing | undefined {
  return caches.find(isGlobalCache);
}

function getBBox(bounds: LngLatBounds): BBox {
  return [
    bounds.getWest(),
    bounds.getSouth(),
    bounds.getEast(),
    bounds.getNorth(),
  ];
}

export function getBounds(bbox: BBox) {
  return new LngLatBounds([bbox[0], bbox[1]], [bbox[2], bbox[3]]);
}

function boundingPolygon(bounds: LngLatBounds): Polygon {
  let _bounds = getBBox(bounds);
  return bboxPolygon(_bounds).geometry;
}

export function boundsForPolygon(polygon: Polygon): LngLatBounds {
  return getBounds(bbox(polygon));
}
