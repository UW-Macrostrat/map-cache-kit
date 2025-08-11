import hyper from "@macrostrat/hyper";
import {
  DetailsPanel,
  FloatingNavbar,
  MapAreaContainer,
  MapLoadingButton,
  MapView,
  PanelCard,
  useBasicMapStyle,
} from "@macrostrat/map-interface";
import styles from "./App.module.sass";
import "@macrostrat/style-system/dist/style-system.css";
import "@blueprintjs/core/lib/css/blueprint.css";
import { Button, FormGroup, SegmentedControl, Tag } from "@blueprintjs/core";
import { useRef, useState } from "react";
import { useQueryState, useRequestTransformer } from "./utils";
import { useAPIResult } from "@macrostrat/ui-components";
import { useMapRef, useMapStyleOperator } from "@macrostrat/mapbox-react";
import { setGeoJSON } from "@macrostrat/mapbox-utils";
import type { Polygon } from "geojson";
import { bbox } from "@turf/bbox";
import { CachePanelView } from "./cache-list";
import { cacheURLAtom } from "./utils";
import { useAtom } from "jotai";

const h = hyper.styled(styles);

const mapboxToken = import.meta.env.VITE_MAPBOX_ACCESS_TOKEN;

const satelliteStyle = "mapbox://styles/jczaplewski/cl51esfdm000e14mq51erype3";

export default function App() {
  const [cacheURL] = useAtom(cacheURLAtom);
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

  const detailPanel = h(
    DetailsPanel,
    {
      title: "Cache regions",
    },
    h("div.cache-areas-inner", [
      h(CachePanelView, {
        data: {
          caches: regions ?? [],
        },
        dispatch: () => {},
      }),
    ]),
  );

  const overlayStyles = [
    {
      sources: {
        cacheRegions: {
          type: "geojson",
          data: {
            type: "FeatureCollection",
            features: [],
          },
        },
      },
      layers: [
        {
          id: "cacheRegions-fill",
          type: "fill",
          source: "cacheRegions",
          paint: {
            "fill-color": "#f08",
            "fill-opacity": 0.1,
          },
        },
        {
          id: "cacheRegions-outline",
          type: "line",
          source: "cacheRegions",
          paint: {
            "line-color": "#f08",
            "line-width": 2,
          },
        },
      ],
    },
  ];

  return h("div.app", [
    h(
      MapPage,
      {
        key: refreshCounter.current,
        mapboxToken,
        style,
        title: "Map caches",
        detailPanel,
        overlayStyles,
        controls: h("div.cache-controls", [
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
        transformRequest: useRequestTransformer(cacheURL),
      },
      h(CacheRegionsLayer, { regions }),
    ),
  ]);
}

interface CacheRegionData {
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

function CacheRegionsLayer({ regions }) {
  useMapStyleOperator(
    (map) => {
      setGeoJSON(map, "cacheRegions", {
        type: "FeatureCollection",
        features: regions
          .filter((d) => !d.isGlobal)
          .map((region) => ({
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
  const mapRef = useMapRef();

  if (regions == null) return null;

  if (regions.length === 0) {
    return h("div.cache-list", h("p", "No cache regions available."));
  }
  return h(
    "div.cache-list",
    regions.map((region) => {
      return h(
        "div.cache-item",
        {
          key: region.id,
          onClick() {
            console.log(region.definition.geometry);
            const bounds = bbox(region.definition.geometry);

            mapRef.current?.fitBounds(bounds, {
              duration: 500,
            });
          },
        },
        [
          h("h3", region.description.name),
          h("p", `Created: ${region.description.created}`),
          h("p", `Updated: ${region.description.updated}`),
          h("p", [h.if(region.isGlobal)(Tag, "global")]),
        ],
      );
    }),
  );
}

function NewCacheButton() {
  return h("div.new-cache", [
    h(
      Button,
      {
        onClick: () => {
          alert("Feature not implemented yet.");
        },
      },
      "Create new cache",
    ),
  ]);
}

export function MapPage({
  title = "Map inspector",
  headerElement = null,
  transformRequest = null,
  mapPosition = null,
  mapboxToken = null,
  controls = null,
  children = null,
  style,
  bounds = null,
  fitViewport = true,
  detailPanel = null,
  ...rest
}) {
  /* We apply a custom style to the panel container when we are interacting
    with the search bar, so that we can block map interactions until search
    bar focus is lost.
    We also apply a custom style when the infodrawer is open so we can hide
    the search bar on mobile platforms
  */

  const [isOpen, setOpen] = useState(false);

  return h(
    MapAreaContainer,
    {
      navbar: h(FloatingNavbar, {
        rightElement: h(MapLoadingButton, {
          large: true,
          active: isOpen,
          onClick: () => setOpen(!isOpen),
          style: {
            marginRight: "-5px",
          },
        }),
        headerElement,
        title,
      }),
      contextPanel: h(PanelCard, [controls]),
      detailPanel,
      contextPanelOpen: isOpen,
      fitViewport,
    },
    h(
      MapView,
      {
        style,
        transformRequest,
        mapPosition,
        projection: { name: "globe" },
        mapboxToken,
        bounds,
        ...rest,
      },
      children,
    ),
  );
}
