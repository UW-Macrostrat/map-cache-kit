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
  cacheModeAtom,
} from "./state.ts";
import { useMapStyleOperator } from "@macrostrat/mapbox-react";
import { setGeoJSON } from "@macrostrat/mapbox-utils";
import { CachePanelView } from "./cache-list";
import { type Atom, atom, useAtom, useAtomValue } from "jotai";
import { type MapCacheLayer, MapCachePriority } from "./cache-list/types.ts";

const h = hyper.styled(styles);

const mapboxToken = import.meta.env.VITE_MAPBOX_ACCESS_TOKEN;

const refreshForceAtom: Atom<number> = atom((get) => {
  get(requestTransformerAtom);
  return Math.random();
});

export default function App() {
  const [transformRequest] = useAtom(requestTransformerAtom);
  const [style] = useAtom(mapStyleAtom);

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
          id: "cacheRegions-outline",
          type: "line",
          source: "cacheRegions",
          paint: {
            "line-color": "#000",
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
        mapboxToken,
        style,
        title: "Map caches",
        detailPanel,
        overlayStyles,
        controls: h("div.cache-controls", [
          h(BasemapControl),
          h(CacheModeControl),
        ]),
        transformRequest,
      },
      [h(CacheRegionsLayer), h(CacheWebsocketConnector)],
    ),
  ]);
}

function CacheWebsocketConnector() {
  useCacheWebSocket();
  return null;
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

function BasemapControl({ inline = false }) {
  const [basemap, setBasemap] = useAtom(basemapAtom);
  return h(FormGroup, { label: "Basemap", inline }, [
    h(SegmentedControl, {
      size: "small",
      options: [
        { label: "Basic", value: "basic" },
        { label: "Satellite", value: "satellite" },
        { label: "Geology", value: "bedrock" },
      ],
      onValueChange(value) {
        setBasemap(value as MapCacheLayer);
      },
      value: basemap,
    }),
  ]);
}

function CacheModeControl({ inline = false }) {
  const [cacheMode, setCacheMode] = useAtom(cacheModeAtom);
  return h(FormGroup, { label: "Cache mode", inline }, [
    h(SegmentedControl, {
      size: "small",
      options: [
        { label: "Network", value: MapCachePriority.Network },
        {
          label: "Fallback",
          value: MapCachePriority.CacheThenNetwork,
        },
        { label: "Cache", value: MapCachePriority.Cache },
      ],
      onValueChange(value: MapCachePriority) {
        setCacheMode(value);
      },
      value: cacheMode,
    }),
  ]);
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
  const refreshCounter = useAtomValue(refreshForceAtom);

  return h(
    MapAreaContainer,
    {
      key: refreshCounter,
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
