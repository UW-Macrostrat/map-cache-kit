import { useState } from "react";
import { type CacheRegionData, MapCachePriority } from "./cache-list/types.ts";
import { atomWithHash } from "jotai-location";
import { atom } from "jotai";
import { atomWithRefresh } from "jotai/utils";

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

export const cacheURLAtom = atom(import.meta.env.VITE_CACHE_URL);

export const cacheRegionsAtom = atomWithRefresh(async (get) => {
  const cacheURL = get(cacheURLAtom);
  const res = await fetch(cacheURL + "/regions");
  if (!res.ok) {
    throw new Error(`Failed to fetch cache regions: ${res.statusText}`);
  }
  const data = await res.json();
  return data as CacheRegionData[];
});

export const cacheRegionsGeoJSONAtom = atom(async (get) => {
  const cacheRegions = await get(cacheRegionsAtom);

  return {
    type: "FeatureCollection",
    features: cacheRegions
      .filter((d) => !d.isGlobal)
      .map((region) => ({
        type: "Feature",
        id: region.id,
        properties: {
          name: region.description.name,
          description: region.description,
        },
        geometry: region.definition.geometry,
      })),
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

interface QueryStateOptions<T> {
  defaultValue: T;
  validValues?: T[] | null;
  parseValue?: (value: string) => T;
  setValue?: (value: T) => string;
}

export function useQueryState<T = string>(
  key: string,
  options: QueryStateOptions<T> | null = null,
): [T, (value: T) => void] {
  // Use state that is managed by a query parameter

  const {
    defaultValue,
    validValues,
    parseValue = (d) => d,
    setValue = (d) => d,
  } = options ?? {};

  const [state, setState] = useState(() => {
    const urlParams = new URLSearchParams(window.location.search);
    const value = urlParams.get(key);
    if (value == null) {
      return defaultValue;
    }
    // Parse the value if a parse function is provided
    let val = parseValue(value);
    if (validValues) {
      // Check if the value is valid
      if (!validValues.includes(val)) {
        console.warn(`Invalid value for ${key}: ${val}`);
        val = null;
      }
    }
    return val ?? defaultValue;
  });

  // Update the URL when the state changes
  const setQueryState = (newValue: T) => {
    const urlParams = new URLSearchParams(window.location.search);
    if (newValue === null || newValue == defaultValue) {
      urlParams.delete(key);
    } else {
      urlParams.set(key, setValue(newValue));
    }
    // If URL params are empty, remove the '?' from the URL
    let params = urlParams.toString();
    if (params.length > 0) {
      params = "?" + params;
    }
    window.history.replaceState(null, "", window.location.pathname + params);
    setState(newValue);
  };

  return [state, setQueryState];
}
