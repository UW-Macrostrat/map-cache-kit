import h from "@macrostrat/hyper";
import { DevMapPage } from "@macrostrat/map-interface";
import "./App.css";
import "@macrostrat/style-system/dist/style-system.css";
import "@blueprintjs/core/lib/css/blueprint.css";

const mapboxToken = import.meta.env.VITE_MAPBOX_ACCESS_TOKEN;
const cacheURL = import.meta.env.VITE_CACHE_URL;

export default function App() {
  return h(
    "div.app",
    h(DevMapPage, {
      mapboxToken,
      title: "Map cache utils",
      transformRequest: (req, type) => {
        // Extract the domain from the request URL
        const url = new URL(req);
        const domain = url.hostname;
        const scheme = url.protocol;

        const baseURL = scheme+"//"+domain;

        const newPath = req.replace(baseURL, cacheURL + "/tiles");

        const newURL = new URL(newPath);

        // Get query parameters
        const params = new URLSearchParams(url.search);

        // Add x-cache- parameters
        params.set("x-cache-domain", domain);
        params.set("x-cache-mode", "cache-then-network");

        newURL.search = params.toString();

        // Log the new URL
        console.log("Transformed URL:", newURL);

        return {
          url: newURL.toString(),
        }
      }
    }),
  );
}
