import { atom, useAtomValue, useSetAtom } from "jotai";
import { atomWithHash } from "jotai-location";
import { atomWithRefresh } from "jotai/utils";
import type { Feature, Polygon } from "geojson";
import { bboxPolygon } from "@turf/bbox-polygon";
import type { MapPosition } from "@macrostrat/mapbox-utils";
import type { LngLat, Map, StyleSpecification } from "mapbox-gl";
import { getMapboxStyle, mergeStyles } from "@macrostrat/mapbox-utils";
import {
  type CacheCreationInfo,
  type CacheData,
  type CacheRegionProgress,
  type DownloadProgressData,
  MapCacheLayer,
  type MapCacheListing,
  MapCachePriority,
} from "./cache-list/types.ts";
import { getRegionName } from "./utils.ts";
import { geologyStyleFragment } from "./cache-list/map-style";
import { useEffect } from "react";
import { useReconnectableWebSocket } from "./cache-list/web-socket.ts";
import { getDefaultStore } from "jotai";

const jotaiStore = getDefaultStore();

export const cacheAPIBaseURL = import.meta.env.VITE_CACHE_URL;
const mapboxAccessToken = import.meta.env.VITE_MAPBOX_ACCESS_TOKEN;

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
      return MapCacheLayer.Basic; // Default to basic if invalid
    },
  },
);

export const cacheDataAtom = atomWithRefresh(async (get) => {
  const res = await fetch(cacheAPIBaseURL + "/regions");
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
  return (request, type) => {
    // Extract the domain from the request URL
    const url = new URL(request);
    const domain = url.hostname;
    const scheme = url.protocol;

    const baseURL = scheme + "//" + domain;

    const newPath = request.replace(baseURL, cacheAPIBaseURL + "/tiles");

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

export const showCacheFormAtom = atom(false);

interface CacheAreaProps {
  minZoom: number;
  maxZoom: number;
  candidate?: boolean;
}

export type CacheArea = Feature<Polygon, CacheAreaProps>;

export const candidateCacheAreaAtom = atom<CacheArea | null>((get) => {
  const map = get(mapAtom);
  const showCacheForm = get(showCacheFormAtom);

  if (map == null || !showCacheForm) {
    return null;
  }

  // Need this to ensure that the map position updates
  const mapPosition = get(mapPositionAtom);
  const minZoom = Math.min(17, Math.floor(mapPosition.target.zoom));
  const maxZoom = Math.min(20, minZoom + 4);

  const bounds = map.getBounds();

  const ll = bounds.getSouthWest();
  const ur = bounds.getNorthEast();

  return bboxPolygon([ll.lng, ll.lat, ur.lng, ur.lat], {
    properties: { candidate: true, minZoom, maxZoom },
    id: -1,
  });
});

/** Cache creation */

interface CacheLayers {
  bedrock: boolean;
  basemap: boolean;
  satellite: boolean;
}

export interface CacheFormData extends CacheLayers {
  name: string;
  area: CacheArea;
  error: string | null;
}

export const cacheLayersAtom = atom<CacheLayers>({
  bedrock: true,
  basemap: true,
  satellite: false,
});

const userProvidedRegionNameAtom = atom<string>();

export function setRegionName(name: string | null) {
  // Action to set the user-provided region name
  jotaiStore.set(userProvidedRegionNameAtom, name);
}

type RegionNameInfo = {
  name: string;
  isUserProvided: boolean;
};

// Lazy atom for name API call
const regionNameAtom = atom<Promise<RegionNameInfo>>(async (get) => {
  const regionName = get(userProvidedRegionNameAtom);
  if (regionName != null && regionName.trim() !== "") {
    return {
      name: regionName.trim(),
      isUserProvided: true,
    };
  }

  /** Otherwise, get the name from the map position */

  const location = get(mapPositionAtom);
  if (location == null) {
    return "Unknown region";
  }

  const { zoom, ...center } = location.target;

  return {
    name: await getRegionName(center as LngLat, zoom, mapboxAccessToken),
    isUserProvided: false,
  };
});

export const newCacheErrorAtom = atom<string | null>(null);

export const newCacheDataAtom = atom<Promise<CacheFormData>>(async (get) => {
  const showForm = get(showCacheFormAtom);
  if (!showForm) {
    return null;
  }

  const cacheArea = get(candidateCacheAreaAtom);
  const layerInfo = get(cacheLayersAtom);
  const regionName = await get(regionNameAtom);
  const styles = await get(cacheStyleJSONAtom);

  return {
    name: regionName.name,
    area: cacheArea,
    layers: createLayerList(layerInfo),
    styles,
    error: get(newCacheErrorAtom),
  };
});

const downloadProgressAtom = atom<DownloadProgressData>({});

export function useDownloadProgress(
  regionID: number,
): CacheRegionProgress | null {
  return useAtomValue(downloadProgressAtom)[regionID] ?? null;
}

type PartialProgress = Omit<CacheRegionProgress, "progress" | "hasErrors">;

const downloadProgressUpdateAtom = atom(
  null,
  (get, set, value: PartialProgress) => {
    const progress = get(downloadProgressAtom);
    set(downloadProgressAtom, {
      ...progress,
      [value.regionID]: extendProgress(value),
    });
  },
);

function extendProgress(progress: PartialProgress): CacheRegionProgress {
  return {
    ...progress,
    progress:
      (progress.tilesDownloaded +
        progress.resourcesDownloaded +
        progress.tilesFailed +
        progress.resourcesFailed) /
      (progress.tilesTotal + progress.resourcesTotal),
    hasErrors: progress.tilesFailed + progress.resourcesFailed > 0,
  };
}

export function useCacheRegions(): MapCacheListing[] {
  // Hook to get the list of cache regions with progress
  return useAtomValue(cacheDataAtom)?.regions ?? [];
}

export function useCacheWebSocket() {
  const webSocket = useReconnectableWebSocket(
    cacheAPIBaseURL + "/regions/events",
  );

  const setDownloadProgress = useSetAtom(downloadProgressUpdateAtom);

  useEffect(() => {
    const msg = webSocket.lastJsonMessage as CacheRegionProgress | null;
    if (msg == null) {
      return;
    }
    setDownloadProgress(msg);
  }, [webSocket.lastJsonMessage]);

  useEffect(() => {
    console.log("Status:", webSocket.readyState);
  }, [webSocket.readyState]);
}

const cacheStyleJSONAtom = atom<Promise<StyleSpecification[]>>(async (get) => {
  /** A list of style JSON files that can be used to define the cache */
  const layers = get(cacheLayersAtom);
  return await getStylesForLayers(layers);
});

const allLayers: CacheLayers = {
  basemap: true,
  satellite: true,
  bedrock: true,
};

async function getStylesForLayers(layers: CacheLayers) {
  const styles: StyleSpecification[] = [];
  if (layers.basemap) {
    const basic = await jotaiStore.get(basicStyleAtom);
    styles.push(basic);
  }
  if (layers.satellite) {
    const satellite = await jotaiStore.get(satelliteStyleAtom);
    styles.push(satellite);
  }
  if (layers.bedrock) {
    styles.push(geologyStyleFragment as StyleSpecification);
  }
  return styles;
}

const satelliteStyle = "mapbox://styles/jczaplewski/cl51esfdm000e14mq51erype3";
const basicStyle = "mapbox://styles/jczaplewski/cl3w3bdai001f14ob27ckmpxz";

function mapboxStyleAtom(style: string) {
  // Atom to get a Mapbox style by its URL
  return atom<Promise<StyleSpecification>>(
    async (get): Promise<StyleSpecification> => {
      return (await getMapboxStyle(style, {
        access_token: mapboxAccessToken,
      })) as StyleSpecification;
    },
  );
}

const satelliteStyleAtom = mapboxStyleAtom(satelliteStyle);
const basicStyleAtom = mapboxStyleAtom(basicStyle);

export const mapStyleAtom = atom(async (get) => {
  const basemap = get(basemapAtom);
  if (basemap === "satellite") {
    return await get(satelliteStyleAtom);
  }
  const basicStyle = await get(basicStyleAtom);
  if (basemap === "basic") {
    return basicStyle;
  }
  return mergeStyles(basicStyle, geologyStyleFragment);
});

mapStyleAtom.debugLabel = "mapStyleAtom";

const cacheCreateDataAtom = atom(async (get) => {
  const cache = await get(newCacheDataAtom);
  if (cache == null) {
    return null;
  }

  const { area, name } = cache;
  const { geometry, properties } = area;

  return {
    styles: await get(cacheStyleJSONAtom),
    geometry,
    layers: createLayerList(cache),
    pixel_ratio: 2,
    name,
    max_zoom: properties.maxZoom,
    min_zoom: properties.minZoom,
  };
});

const resetCachesAtom = atom(null, (get, set) => {
  set(cacheDataAtom);
  set(showCacheFormAtom, false);
  set(userProvidedRegionNameAtom, null);
});

/** Actions */

export async function deleteAllCaches() {
  // Utility function to delete all caches (for testing)
  const response = await fetch(cacheAPIBaseURL + "/regions", {
    method: "DELETE",
  });
  if (!response.ok) {
    throw new Error(
      `Failed to delete all cache regions: ${response.statusText}`,
    );
  }
  jotaiStore.set(resetCachesAtom);
}

export async function refreshDefinitions() {
  // Refresh the cache definitions from the API
  const response = await fetch(cacheAPIBaseURL + "/regions/refresh", {
    method: "POST",
  });
  if (!response.ok) {
    throw new Error(
      `Failed to refresh cache definitions: ${response.statusText}`,
    );
  }
  jotaiStore.set(resetCachesAtom);
}

export async function createCache() {
  const data = await jotaiStore.get(cacheCreateDataAtom);
  return await createCacheInternal(data);
}

async function createCacheInternal(data: CacheCreationInfo) {
  // Post to the cache API to create a new cache
  const response = await fetch(cacheAPIBaseURL + "/regions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify(data),
  });
  const { error } = await response.json();
  if (error != null) {
    throw error;
  }
  jotaiStore.set(resetCachesAtom);
}

export async function createGlobalCache() {
  const data = {
    geometry: {
      type: "Polygon",
      coordinates: [
        [
          [-180, -90],
          [180, -90],
          [180, 90],
          [-180, 90],
          [-180, -90],
        ],
      ],
    } as Polygon,
    min_zoom: 0,
    max_zoom: 4,
    pixel_ratio: 2,
    styles: await getStylesForLayers(allLayers),
    name: "Global",
    layers: createLayerList(allLayers),
  };
  return await createCacheInternal(data);
}

export async function deleteCache(id: number) {
  const response = await fetch(`${cacheAPIBaseURL}/regions/${id}`, {
    method: "DELETE",
  });
  if (!response.ok) {
    throw new Error(`Failed to delete cache region: ${response.statusText}`);
  }
  jotaiStore.set(resetCachesAtom);
}

/** Helpers */

function createLayerList(info: CacheLayers): string[] {
  const layers: string[] = [];
  if (info.basemap) {
    layers.push("basemap");
  }
  if (info.bedrock) {
    layers.push("bedrock");
  }
  if (info.satellite) {
    layers.push("satellite");
  }
  return layers;
}
