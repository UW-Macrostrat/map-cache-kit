import { LngLat } from "mapbox-gl";

// TODO: move this function to a shared library

type ResultType =
  | "country"
  | "region"
  | "postcode"
  | "district"
  | "place"
  | "locality"
  | "neighborhood"
  | "address"
  | "poi";

function getTypesForZoom(zoom: number): ResultType[] | null {
  const types: ResultType[] = ["country"];
  if (zoom > 7) {
    types.push("region", "country");
  }
  if (zoom > 9) {
    types.push("district");
  }
  if (zoom > 11) {
    types.push("place");
  }
  if (zoom > 13) {
    types.push("locality");
  }
  if (zoom > 14) {
    types.push("neighborhood");
  }
  return types;
}

export async function getNamedLocation(
  location: LngLat,
  zoom: number,
  accessToken: string,
) {
  const baseURL = `https://api.mapbox.com/geocoding/v5/mapbox.places/${location.lng},${location.lat}.json`;
  const types = getTypesForZoom(zoom);

  const url =
    baseURL +
    "?" +
    new URLSearchParams({
      access_token: accessToken,
      types: types?.join(","),
    } as Record<string, string>);

  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Failed to fetch named location: ${response.statusText}`);
  }
  const data = await response.json();
  const result = data.features[0];
  return result?.place_name;
}
