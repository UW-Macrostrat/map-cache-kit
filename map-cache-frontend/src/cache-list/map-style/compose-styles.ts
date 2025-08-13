import { Sources, Layers, mapStyleVersion } from "~/components/map/map-style";
import { MapCacheLayer } from "../types";
import { mergeStyles } from "@macrostrat/mapbox-utils";
import satellite from "./style-jczaplewski-cl51esfdm000e14mq51erype3-satellite.json";
import basic from "./style-jczaplewski-cl3w3bdai001f14ob27ckmpxz-basic.json";
export { mapStyleVersion };

export function styleNameForLayers(layers: Set<MapCacheLayer>) {
  let layerList = Array.from(layers).sort().join("+");
  let name = `rockd-cache.v${mapStyleVersion}.${layerList}`;
  return name;
}

export async function composeLayerStylesheets(
  layers: Set<MapCacheLayer>,
  apiKey?: string,
) {
  /** This function composes Rockd's style layers into a unified stylesheet,
   * for the purposes of building a single map style that can be cached by
   * the map cache provider.
   */

  // only glyphs and sprites from the first map will be used, currently.

  let style: Partial<mapboxgl.Style> = {
    name: "rockd-cache",
    version: 8 as 8,
    sources: {},
    layers: [],
  };

  if (layers.has(MapCacheLayer.Basic)) {
    style = mergeStyles(style, basic as any) as any;
    // @ts-ignore
    style.layers = [...style.layers, ...basic.layers];
  }

  if (layers.has(MapCacheLayer.Satellite)) {
    style = mergeStyles(style, satellite as any) as any;
  }

  if (layers.has(MapCacheLayer.Bedrock)) {
    style = mergeStyles(style, {
      // Casts prevent literal‑8 / union mismatches
      sources: Sources as any,
      layers: Layers as any,
    } as any) as any;
  }

  // This cache name must be set properly or else we have invalid cache names
  return {
    ...style,
    name: styleNameForLayers(layers),
    version: 8 as 8,
  };
}
