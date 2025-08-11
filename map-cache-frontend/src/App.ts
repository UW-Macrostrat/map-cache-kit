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
import { FormGroup, SegmentedControl, Tag } from "@blueprintjs/core";
import { useState } from "react";
import {
  cacheRegionsGeoJSONAtom,
  requestTransformerAtom,
  useQueryState,
} from "./utils";
import { useAPIResult } from "@macrostrat/ui-components";
import { useMapStyleOperator } from "@macrostrat/mapbox-react";
import { setGeoJSON } from "@macrostrat/mapbox-utils";
import { bbox } from "@turf/bbox";
import { CachePanelView } from "./cache-list";
import { cacheURLAtom } from "./utils";
import { type Atom, atom, useAtom } from "jotai";

const h = hyper.styled(styles);

const mapboxToken = import.meta.env.VITE_MAPBOX_ACCESS_TOKEN;

const satelliteStyle = "mapbox://styles/jczaplewski/cl51esfdm000e14mq51erype3";

const refreshForceAtom: Atom<number> = atom((get) => {
  get(requestTransformerAtom);
  return Math.random();
});

export default function App() {
  const [cacheURL] = useAtom(cacheURLAtom);
  const [transformRequest] = useAtom(requestTransformerAtom);
  const [basemap, setBasemap] = useQueryState<"basic" | "satellite">(
    "basemap",
    {
      defaultValue: "basic",
      validValues: ["basic", "satellite"],
    },
  );
  const [refreshCounter] = useAtom(refreshForceAtom);

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
              ],
              onValueChange: (value) => {
                setBasemap(value);
              },
              value: basemap,
            }),
          ]),
        ]),
        transformRequest,
      },
      h(CacheRegionsLayer, { regions }),
    ),
  ]);
}

function CacheRegionsLayer({ regions }) {
  const [geoJSONData] = useAtom(cacheRegionsGeoJSONAtom);
  useMapStyleOperator(
    (map) => {
      setGeoJSON(map, "cacheRegions", geoJSONData);
    },
    [regions],
  );

  return null;
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
