import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import App from "./App";
import h from "@macrostrat/hyper";
import { DarkModeProvider } from "@macrostrat/ui-components";
import { FocusStyleManager } from "@blueprintjs/core";

// Enable focus styles for BlueprintJS components
FocusStyleManager.onlyShowFocusOnTabs();

createRoot(document.getElementById("root")!).render(
  h(StrictMode, h(DarkModeProvider, h(App))),
);
