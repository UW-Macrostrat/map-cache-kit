import hyper from "@macrostrat/hyper";
import {
  DetailsPanel,
  FloatingNavbar,
  MapAreaContainer,
  MapLoadingButton,
  MapView,
  PanelCard,
} from "@macrostrat/map-interface";
import styles from "./App.module.sass";
import "@macrostrat/style-system/dist/style-system.css";
import "@blueprintjs/core/lib/css/blueprint.css";
import { FormGroup, SegmentedControl } from "@blueprintjs/core";
import { useState } from "react";
import {
  basemapAtom,
  cacheRegionsGeoJSONAtom,
  requestTransformerAtom,
  mapAtom,
  mapPositionAtom,
  mapStyleAtom,
  useCacheWebSocket,
} from "./state.ts";
import { useMapStyleOperator } from "@macrostrat/mapbox-react";
import { setGeoJSON } from "@macrostrat/mapbox-utils";
import { CachePanelView } from "./cache-list";
import { type Atom, atom, useAtom } from "jotai";
import type { MapCacheLayer } from "./cache-list/types.ts";

const h = hyper.styled(styles);

const mapboxToken = import.meta.env.VITE_MAPBOX_ACCESS_TOKEN;

const refreshForceAtom: Atom<number> = atom((get) => {
  get(requestTransformerAtom);
  return Math.random();
});

export default function App() {
  const [transformRequest] = useAtom(requestTransformerAtom);
  const [basemap, setBasemap] = useAtom(basemapAtom);
  const [refreshCounter] = useAtom(refreshForceAtom);
  const [style] = useAtom(mapStyleAtom);

  useCacheWebSocket();

  const detailPanel = h(
    DetailsPanel,
    {
      title: "Cache regions",
    },
    h("div.cache-areas-inner", [
      h(CachePanelView, {
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
            "line-dasharray": [
              "case",
              // If the region is a candidate, use a dashed line
              ["coalesce", ["get", "candidate"], false],
              ["literal", [2, 2]],
              ["literal", [1, 0]],
            ],
          },
        },
      ],
    },
  ];

  return h("div.app", [
    h(
      MapPage,
      {
        key: refreshCounter,
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
                { label: "Geology", value: "bedrock" },
              ],
              onValueChange: (value) => {
                setBasemap(value as MapCacheLayer);
              },
              value: basemap,
            }),
          ]),
        ]),
        transformRequest,
      },
      h(CacheRegionsLayer),
    ),
  ]);
}

function CacheRegionsLayer() {
  const [geoJSONData] = useAtom(cacheRegionsGeoJSONAtom);
  useMapStyleOperator(
    (map) => {
      console.log("Setting cache regions GeoJSON data");
      setGeoJSON(map, "cacheRegions", geoJSONData);
    },
    [geoJSONData],
  );

  return null;
}

export function MapPage({
  title = "Map inspector",
  headerElement = null,
  transformRequest = null,
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
  const [_, onMapLoaded] = useAtom(mapAtom);
  const [__, onMapMoved] = useAtom(mapPositionAtom);

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
        projection: { name: "globe" },
        mapboxToken,
        bounds,
        onMapLoaded,
        onMapMoved,
        ...rest,
      },
      children,
    ),
  );
}
