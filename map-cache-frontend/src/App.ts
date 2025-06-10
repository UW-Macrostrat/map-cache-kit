import h from "@macrostrat/hyper";
import { DevMapPage, useBasicMapStyle } from "@macrostrat/map-interface";
import "./App.css";
import "@macrostrat/style-system/dist/style-system.css";
import "@blueprintjs/core/lib/css/blueprint.css";
import { SegmentedControl, FormGroup } from "@blueprintjs/core";
import { useRef } from "react";
import { useQueryState, useRequestTransformer } from "./utils";
import { FlexRow } from "@macrostrat/ui-components";

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

  return h(
    "div.app",
    h(FlexRow, [
      h(DevMapPage, {
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
      }),
      h("div.cache-areas", [h("h2", "Cache areas")]),
    ]),
  );
}
