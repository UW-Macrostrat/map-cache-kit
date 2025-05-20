import h from "@macrostrat/hyper";
import { DevMapPage } from "@macrostrat/map-interface";
import "./App.css";
import "@macrostrat/style-system/dist/style-system.css";
import "@blueprintjs/core/lib/css/blueprint.css";
import { SegmentedControl, FormGroup } from "@blueprintjs/core";
import { useRef } from "react";
import { useQueryState, useRequestTransformer } from "./utils";

const mapboxToken = import.meta.env.VITE_MAPBOX_ACCESS_TOKEN;
const cacheURL = import.meta.env.VITE_CACHE_URL;

const styles = {
  satellite: "mapbox://styles/jczaplewski/cl51esfdm000e14mq51erype3",
  basic: "mapbox://styles/jczaplewski/cl3w3bdai001f14ob27ckmpxz",
};

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

  return h(
    "div.app",
    h(DevMapPage, {
      key: refreshCounter.current,
      mapboxToken,
      style: styles[basemap],
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
    }),
  );
}
