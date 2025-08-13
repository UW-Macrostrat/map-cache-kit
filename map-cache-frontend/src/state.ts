import {
  type CacheData,
  MapCacheLayer,
  MapCachePriority,
} from "./cache-list/types.ts";
import { atomWithHash } from "jotai-location";
import { atom } from "jotai";
import { atomWithRefresh } from "jotai/utils";
import type { Map } from "mapbox-gl";
import type { MapPosition } from "@macrostrat/mapbox-utils";
import { bboxPolygon } from "@turf/bbox-polygon";
import type { Feature, Polygon } from "geojson";
import type { LngLat } from "mapbox-gl";
import { getNamedLocation } from "./utils.ts";
import { getMapboxStyle, mergeStyles } from "@macrostrat/mapbox-utils";
import { geologyStyleFragment } from "./cache-list/map-style";
import type { StyleSpecification } from "mapbox-gl";

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

export const cacheAPIBaseURL = import.meta.env.VITE_CACHE_URL;

export const mapboxTokenAtom = atom(import.meta.env.VITE_MAPBOX_ACCESS_TOKEN);

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
  const maxZoom = Math.min(20, minZoom + 3);

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
}

export const cacheLayersAtom = atom<CacheLayers>({
  bedrock: true,
  basemap: true,
  satellite: false,
});

// Lazy atom for name API call
export const locationNameAtom = atom<Promise<string>>(async (get, set) => {
  const location = get(mapPositionAtom);
  if (location == null) {
    return "Unknown location";
  }
  const apiKey = get(mapboxTokenAtom);

  const { zoom, ...center } = location.target;

  return await getNamedLocation(center as LngLat, zoom, apiKey);
});

export const newCacheDataAtom = atom<CacheFormData>(async (get) => {
  const showForm = get(showCacheFormAtom);
  if (!showForm) {
    return null;
  }

  const cacheArea = get(candidateCacheAreaAtom);

  const name = await get(locationNameAtom);
  const layers = get(cacheLayersAtom);
  const styles = await get(cacheStyleJSONAtom);

  return {
    name,
    area: cacheArea,
    ...layers,
    styles,
  };
});

const cacheStyleJSONAtom = atom<Promise<StyleSpecification[]>>((get) => {
  /** A list of style JSON files that can be used to define the cache */
  const geology = geologyStyleFragment;

  const layers = get(cacheLayersAtom);
  const styles: StyleSpecification[] = [];
  if (layers.basemap) {
    const basic = get(basicStyleAtom);
    styles.push(basic);
  }
  if (layers.satellite) {
    const satellite = get(satelliteStyleAtom);
    styles.push(satellite);
  }
  if (layers.bedrock) {
    styles.push(geology);
  }
  return styles;
});

const satelliteStyle = "mapbox://styles/jczaplewski/cl51esfdm000e14mq51erype3";
const basicStyle = "mapbox://styles/jczaplewski/cl3w3bdai001f14ob27ckmpxz";

function mapboxStyleAtom(style: string): Atom<Promise<StyleSpecification>> {
  // Atom to get a Mapbox style by its URL
  return atom(async (get): Promise<StyleSpecification> => {
    const access_token = get(mapboxTokenAtom);
    return (await getMapboxStyle(style, {
      access_token,
    })) as StyleSpecification;
  });
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
