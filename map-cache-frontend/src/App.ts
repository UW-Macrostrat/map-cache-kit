import h from "@macrostrat/hyper";
import { DevMapPage } from "@macrostrat/map-interface";
import "./App.css";
import "@macrostrat/style-system/dist/style-system.css";
import "@blueprintjs/core/lib/css/blueprint.css";

const mapboxToken = import.meta.env.VITE_MAPBOX_ACCESS_TOKEN;

export default function App() {
  return h(
    "div.app",
    h(DevMapPage, {
      mapboxToken,
      title: "Map cache utils",
    }),
  );
}
