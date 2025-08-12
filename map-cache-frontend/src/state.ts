import {
  type CacheData,
  MapCacheLayer,
  MapCachePriority,
} from "./cache-list/types.ts";
import { atomWithHash } from "jotai-location";
import { atom } from "jotai";
import { atomWithRefresh, RESET } from "jotai/utils";
import type { Map } from "mapbox-gl";
import type { MapPosition } from "@macrostrat/mapbox-utils";
import { bboxPolygon } from "@turf/bbox-polygon";
import type { Feature } from "geojson";

export const cacheModeAtom = atomWithHash<MapCachePriority>(
  "map-cache-mode",
  MapCachePriority.CacheThenNetwork,
  {
    serialize: (value) => value.toString(),
    deserialize: (value) => {
      if (value == null) {
        return MapCachePriority.CacheThenNetwork;
      }
      return value as MapCachePriority;
    },
  },
);

export const basemapAtom = atomWithHash<MapCacheLayer>(
  "basemap",
  MapCacheLayer.Basic,
  {
    serialize: (value) => {
      return value;
    },
    deserialize: (value): MapCacheLayer => {
      if (value === "basic" || value === "satellite" || value === "bedrock") {
        return value as MapCacheLayer;
      }
      return "basic"; // Default to basic if invalid
    },
  },
);

export const cacheURLAtom = atom(import.meta.env.VITE_CACHE_URL);
export const mapboxTokenAtom = atom(import.meta.env.VITE_MAPBOX_ACCESS_TOKEN);

export const cacheDataAtom = atomWithRefresh(async (get) => {
  const cacheURL = get(cacheURLAtom);
  const res = await fetch(cacheURL + "/regions");
  if (!res.ok) {
    throw new Error(`Failed to fetch cache regions: ${res.statusText}`);
  }
  const data = await res.json();
  return data as CacheData;
});

export const cacheRegionsGeoJSONAtom = atom(async (get) => {
  const cacheData = await get(cacheDataAtom);
  const regions = cacheData?.regions;

  const features: Feature[] = regions
    .filter((d) => !d.global)
    .map((region) => ({
      type: "Feature",
      id: region.id,
      properties: {
        name: region.description.name,
        description: region.description,
      },
      geometry: region.definition.geometry,
    }));

  const candidateRegion = get(candidateCacheAreaAtom);
  if (candidateRegion !== null) {
    features.push(candidateRegion);
  }

  return {
    type: "FeatureCollection",
    features,
  };
});

export const requestTransformerAtom = atom((get) => {
  const cacheMode = get(cacheModeAtom);
  const cacheURL = get(cacheURLAtom);
  return (request, type) => {
    // Extract the domain from the request URL
    const url = new URL(request);
    const domain = url.hostname;
    const scheme = url.protocol;

    const baseURL = scheme + "//" + domain;

    const newPath = request.replace(baseURL, cacheURL + "/tiles");

    const newURL = new URL(newPath);

    // Get query parameters
    const params = new URLSearchParams(url.search);

    // Add x-cache- parameters
    params.set("x-cache-domain", domain);
    params.set("x-cache-mode", cacheMode);

    newURL.search = params.toString();

    return {
      url: newURL.toString(),
    };
  };
});

export const mapAtom = atom<Map | null>(null);
export const mapPositionAtom = atom<MapPosition | null>(null);

export const showCacheFormAtom = atom(true);

export const candidateCacheAreaAtom = atom<Feature | null>((get) => {
  const map = get(mapAtom);
  const showCacheForm = get(showCacheFormAtom);

  if (map == null || !showCacheForm) {
    return null;
  }

  const mapPosition = get(mapPositionAtom);

  const bounds = map.getBounds();

  const ll = bounds.getSouthWest();
  const ur = bounds.getNorthEast();

  return bboxPolygon([ll.lng, ll.lat, ur.lng, ur.lat], {
    properties: { candidate: true },
    id: -1,
  });
});
