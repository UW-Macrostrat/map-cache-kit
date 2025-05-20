import h from "@macrostrat/hyper";
import { DevMapPage } from "@macrostrat/map-interface";
import "./App.css";
import "@macrostrat/style-system/dist/style-system.css";
import "@blueprintjs/core/lib/css/blueprint.css";
import { SegmentedControl, FormGroup } from "@blueprintjs/core";
import { useCallback, useRef, useState } from "react";

const mapboxToken = import.meta.env.VITE_MAPBOX_ACCESS_TOKEN;
const cacheURL = import.meta.env.VITE_CACHE_URL;

const styles = {
  satellite: "mapbox://styles/jczaplewski/cl51esfdm000e14mq51erype3",
  basic: "mapbox://styles/jczaplewski/cl3w3bdai001f14ob27ckmpxz",
};

export default function App() {
  const [cacheMode, setCacheMode] = useState("cache-then-network");
  const [basemap, setBasemap] = useState<"basic" | "satellite">("satellite");
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
      transformRequest: useRequestTransformer(cacheMode),
    }),
  );
}

function useRequestTransformer(cacheMode) {
  return useCallback(
    (req, type) => {
      // Extract the domain from the request URL
      const url = new URL(req);
      const domain = url.hostname;
      const scheme = url.protocol;

      const baseURL = scheme + "//" + domain;

      const newPath = req.replace(baseURL, cacheURL + "/tiles");

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
    },
    [cacheMode],
  );
}
