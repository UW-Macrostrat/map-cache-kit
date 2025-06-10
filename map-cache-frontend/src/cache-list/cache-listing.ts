import m from "@macrostrat/hyper";
import {
  MapCacheListing,
  OfflineRegionStatus,
  MapCachePriority,
} from "../models";
import { CacheMap } from "./cache-map";
import { useState, memo } from "react";
import {
  findGlobalCache,
  isGlobalCache,
  isStyleCache,
} from "../map-cache.service";

export function CachePanelView({ data, dispatch, cacheMode }) {
  if (data == null) return null;
  const { caches } = data;
  const hasGlobalCache = findGlobalCache(caches ?? []) != null;

  return m("div.cache-list-panel", [
    m.if(!hasGlobalCache)(AddGlobalCacheButton, { dispatch }),
    m(
      NewCacheButton,
      { dispatch },
      m("span", [
        m("span.ion-padding-right", "New cache"),
        m("em", " (current map area)"),
      ]),
    ),
    // @ts-ignore
    m(CacheList, { caches, dispatch }),
    m(CacheSystemControls, { dispatch, totalSize: data?.totalSize, cacheMode }),
  ]);
}

function CacheList({ caches, dispatch }) {
  if (caches == null) {
    return m("div.cache-list-empty", m("ion-spinner"));
  }

  if (caches.length == 0) {
    return m("div.cache-list-empty", m("ion-label", "No caches"));
  }

  return m([
    m(
      "div.ion-list",
      null,
      caches.map((cache) => {
        if (isStyleCache(cache)) {
          return m(StyleCacheItem, { cache, key: cache.id });
        }

        return m(CacheItem, {
          key: cache.id,
          cache,
          dispatch,
        });
      }),
    ),
    m("div.cache-list-spacer"),
  ]);
}

const _Map = memo(CacheMap);

function StyleCacheItem({ cache }: { cache: MapCacheListing }) {
  return null;
}

function _CacheItem({
  cache,
  dispatch,
}: {
  cache: MapCacheListing;
  dispatch(action: CacheManagementAction): void;
}) {
  const isDownloading = cache.offlineStatus?.downloadState == "active";
  const [uiState, setUIState] = useState<CacheUIState>();

  const isGlobal = isGlobalCache(cache);

  const interceptedDispatch = (action: CacheManagementAction) => {
    if (action.type === "delete") {
      setUIState("deleting");
    }
    dispatch(action);
  };

  return m(
    "div.ion-card",
    { class: "cache-card", disabled: uiState == "deleting" },
    [
      m("div.flex-row", [
        m("div.main-column", [
          m("div.ion-card-header", [
            m("div.ion-card-subtitle", [
              isGlobal ? "Global" : (cache.metadata?.name ?? "Unnamed cache"),
            ]),
          ]),
          m("div.ion-card-content", [
            m(CacheLayers, { layers: cache.metadata?.layers }),
            m(CacheStatus, { cache }),
          ]),
          m(CacheControlActionButtons, {
            dispatch: interceptedDispatch,
            cacheId: cache.id,
            isDownloading,
          }),
        ]),
        m(_Map, {
          geometry: cache?.geometry,
          onClick() {
            dispatch({ type: "view", cacheId: cache.id });
          },
        }),
      ]),
    ],
  );
}

const CacheItem = memo(_CacheItem);

function LabeledControl({ label, children }) {
  return m("div.ion-row", { class: "flex-row" }, [
    m("div.ion-col", { size: "auto" }, m("span.ion-label", label)),
    m("div.ion-col", {}, children),
  ]);
}

type CacheUIState = "deleting" | "refreshing" | null;

function CacheSystemControls({
  totalSize,
  dispatch,
  cacheMode,
}: {
  totalSize: number;
  dispatch(action: CacheManagementAction): void;
  cacheMode: MapCachePriority;
  uiState?: CacheUIState;
}) {
  return m("div.ion-card", [
    m("div.ion-card-content", [
      m("div.flex-row", [
        m(LabeledControl, { label: "Total size" }, [
          m(CacheSize, { size: totalSize }),
        ]),
        m("div.spacer"),
        m(
          IconButton,
          {
            icon: "trash",
            color: "danger",
            size: "medium",
            onClick: () => dispatch({ type: "delete-all" }),
          },
          "Delete all",
        ),
      ]),
      m(LabeledControl, { label: "Cache mode" }, [
        m(
          "div.ion-segment",
          {
            value: cacheMode,
          },
          [
            m(SegmentButton, { value: "network", dispatch }, "Network only"),
            m(
              SegmentButton,
              { value: "cache-then-network", dispatch },
              "Cache preferred",
            ),
            m(SegmentButton, { value: "cache", dispatch }, "Cache only"),
          ],
        ),
      ]),
      m("div.flex-row", [
        m("div.spacer"),
        m(
          "div.ion-button",
          {
            size: "small",
            color: "light",
            onClick() {
              dispatch({ type: "delete-ambient" });
            },
          },
          "Clear ambient cache",
        ),
      ]),
    ]),
  ]);
}

function SegmentButton({ value, children, dispatch }) {
  return m(
    "div.ion-segment-button",
    {
      value,
      onClick() {
        dispatch({ type: "set-cache-mode", cacheMode: value });
      },
    },
    children,
  );
}

function CacheLayers({ layers }) {
  if (layers == null) return null;
  return m("div.cache-layers", [
    layers.map((layer) =>
      m("div.ion-chip", { key: layer }, [capitalize(layer), " "]),
    ),
  ]);
}

function CardDownloadState({ data }: { data: OfflineRegionStatus }) {
  if (data?.downloadState != "active") return null;
  const expected = data.requiredResourceCount + data.requiredTileCount;
  const completed = data.completedResourceCount + data.completedTileCount;
  const value = completed / expected;
  return m("div", [m("div.ion-progress-bar", { value })]);
}

function CacheDate({ date }) {
  return m("span.date", date.toLocaleString().split(",")[0]);
}

function CacheDateBlock({ cache }) {
  if (cache.metadata == null) return null;
  const created = new Date(cache.metadata?.created);
  const updated = new Date(cache.metadata?.updated);
  let date = created;
  if (created < updated) {
    date = updated;
  }

  return m("span.date-block", [m("em", m(CacheDate, { date }))]);
}

function CacheStatus({ cache }) {
  const isDownloading = cacheIsDownloading(cache);

  return m("div.cache-status", [
    m.if(isDownloading)(CardDownloadState, {
      data: cache.offlineStatus,
    }),
    m("p.flex-row", [
      m(CacheSizes, { ...cache.sizes }),
      m("span.spacer"),
      m.if(!isDownloading)(CacheDateBlock, { cache }),
    ]),
  ]);
}

function CacheControlActionButtons({
  dispatch,
  cacheId,
  isDownloading = false,
}) {
  const runAction = (action: CacheManagementAction["type"]) => () =>
    dispatch({ type: action, cacheId });

  return m("div.ion-row", { class: "ion-padding-start" }, [
    // m.if(isDownloading)(
    //   IconButton,
    //   {
    //     icon: "pause",
    //     color: "warning",
    //     onClick: runAction("cancel-download"),
    //   },
    //   "Pause download"
    // ),
    // m.if(!isDownloading)(
    //   IconButton,
    //   {
    //     icon: "refresh",
    //     color: "secondary",
    //     onClick: runAction("refresh"),
    //   },
    //   "Refresh"
    // ),
    m(
      IconButton,
      {
        icon: "trash",
        color: "danger",
        onClick: runAction("delete"),
      },
      "Delete",
    ),
  ]);
}

function NewCacheButton({ dispatch, action = "create", ...rest }) {
  return m(IconButton, {
    icon: "add",
    color: "success",
    expand: "block",
    size: "large",
    class: "ion-margin",
    onClick: () => dispatch({ type: action }),
    ...rest,
  });
}

function AddGlobalCacheButton({ dispatch }) {
  return m(
    NewCacheButton,
    {
      action: "create-global",
      color: "secondary",
      icon: "earth",
      dispatch,
    },
    "Create global cache",
  );
}

function IconButton({ icon, onClick, color, children, ...rest }) {
  return m("ion-button", { size: "small", color, onClick, ...rest }, [
    m("ion-icon", { slot: "start", name: icon }),
    " ",
    children,
  ]);
}

function CacheSizes({
  tileSize,
  resourceSize,
  tileCount,
  expectedTileCount = null,
  expanded = false,
}) {
  const totalSize = tileSize + resourceSize;
  return m("span.cache-sizes", [
    m(CacheSize, { size: totalSize }),
    m.if(expanded)([
      " (",
      m(CacheSize, { size: tileSize }),
      " tiles and ",
      m(CacheSize, { size: resourceSize }),
      " resources)",
    ]),
    ", ",
    tileCount,
    m.if(expectedTileCount != null)([" of ", expectedTileCount]),
    " tiles",
  ]);
}

function CacheSize({ size }) {
  const sz = Math.round(size / 1024 / 1024);
  return m("span.size", [sz, " ", m("span.size-unit", "MB")]);
}

function capitalize(str) {
  return str.charAt(0).toUpperCase() + str.slice(1);
}

export type CacheManagementAction =
  | {
      type: "delete" | "view" | "refresh" | "cancel-download";
      cacheId: number;
    }
  | { type: "create-global" | "create" | "delete-all" | "delete-ambient" }
  | { type: "set-cache-mode"; cacheMode: MapCachePriority };

function cacheIsDownloading(cache: MapCacheListing) {
  return cache.offlineStatus?.downloadState == "active";
}
