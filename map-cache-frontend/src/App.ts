import hyper from "@macrostrat/hyper";
import { DevMapPage, useBasicMapStyle } from "@macrostrat/map-interface";
import styles from "./App.module.sass";
import "@macrostrat/style-system/dist/style-system.css";
import "@blueprintjs/core/lib/css/blueprint.css";
import { SegmentedControl, FormGroup } from "@blueprintjs/core";
import { useRef } from "react";
import { useQueryState, useRequestTransformer } from "./utils";
import { FlexRow, useAPIResult } from "@macrostrat/ui-components";
import { useMapStyleOperator } from "@macrostrat/mapbox-react";
import { setGeoJSON } from "@macrostrat/mapbox-utils";
import type { Polygon } from "geojson";

const h = hyper.styled(styles);

const mapboxToken = import.meta.env.VITE_MAPBOX_ACCESS_TOKEN;
const cacheURL = import.meta.env.VITE_CACHE_URL;

const satelliteStyle = "mapbox://styles/jczaplewski/cl51esfdm000e14mq51erype3";

const cacheModeOptions = [
  { label: "Cache", value: "cache" },
  { label: "Fallback", value: "cache-then-network" },
  { label: "Network", value: "network" },
];

const cacheModes = cacheModeOptions.map((option) => option.value);

export default function App() {
  const [cacheMode, setCacheMode] = useQueryState("mode", {
    defaultValue: "cache-then-network",
    validValues: cacheModes,
  });
  const [basemap, setBasemap] = useQueryState<"basic" | "satellite">(
    "basemap",
    {
      defaultValue: "basic",
      validValues: ["basic", "satellite"],
    },
  );
  const refreshCounter = useRef(0);

  const basicStyle = useBasicMapStyle();
  const style = basemap === "basic" ? basicStyle : satelliteStyle;

  const regions: CacheRegionData[] = useAPIResult(cacheURL + "/regions");

  return h("div.app", [
    h(
      DevMapPage,
      {
        key: refreshCounter.current,
        mapboxToken,
        style,
        title: "Map cache utils",
        controls: h("div.cache-controls", [
          h(FormGroup, { label: "Cache mode" }, [
            h(SegmentedControl, {
              options: [
                { label: "Cache", value: "cache" },
                { label: "Fallback", value: "cache-then-network" },
                { label: "Network", value: "network" },
              ],
              onValueChange: (value) => {
                setCacheMode(value);
                refreshCounter.current += 1;
              },
              value: cacheMode,
            }),
          ]),
          h(FormGroup, { label: "Basemap" }, [
            h(SegmentedControl, {
              options: [
                { label: "Basic", value: "basic" },
                { label: "Satellite", value: "satellite" },
              ],
              onValueChange: (value) => {
                setBasemap(value);
              },
              value: basemap,
            }),
          ]),
        ]),
        transformRequest: useRequestTransformer(cacheURL, cacheMode),
      },
      h(CacheRegionsLayer, { regions }),
    ),
    h(
      "div.cache-areas",
      h("div.cache-areas-inner", [
        h("h2", "Cache areas"),
        h(CacheList, { regions }),
        h(
          "p",
          "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.",
        ),
      ]),
    ),
  ]);
}

interface CacheRegionData {
  id: string;
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

function CacheRegionsLayer({ regions }) {
  useMapStyleOperator(
    (map) => {
      setGeoJSON(map, "cacheRegions", {
        type: "FeatureCollection",
        features: regions.map((region) => ({
          type: "Feature",
          id: region.id,
          properties: {
            name: region.name,
            description: region.description,
          },
          geometry: region.definition.geometry,
        })),
      });
    },
    [regions],
  );

  return null;
}

function CacheList({ regions }) {
  if (regions == null) return null;

  if (regions.length === 0) {
    return h("div.cache-list", h("p", "No cache regions available."));
  }
  return h(
    "div.cache-list",
    regions.map((region) =>
      h("div.cache-item", { key: region.id }, [
        h("h3", region.description.name),
        h("p", `Created: ${region.description.created}`),
        h("p", `Updated: ${region.description.updated}`),
      ]),
    ),
  );
}
