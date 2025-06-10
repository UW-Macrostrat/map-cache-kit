import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import App from "./App";
import h from "@macrostrat/hyper";
import { DarkModeProvider } from "@macrostrat/ui-components";

createRoot(document.getElementById("root")!).render(
  h(StrictMode, h(DarkModeProvider, h(App))),
);
