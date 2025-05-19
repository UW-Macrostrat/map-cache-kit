import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import App from "./App";
import h from "@macrostrat/hyper";

createRoot(document.getElementById("root")!).render(h(StrictMode, h(App)));
