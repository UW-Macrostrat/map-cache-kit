import m from "@macrostrat/hyper";
import type { MapCacheListing, OfflineRegionStatus } from "./types";
import { MapCachePriority } from "./types";
import { CacheMap } from "./cache-map";
import { useState, memo } from "react";
import { findGlobalCache, isGlobalCache, isStyleCache } from "./utils";
import { useReconnectableWebSocket } from "./web-socket.ts";
import {
  Button,
  FormGroup,
  SegmentedControl,
  Spinner,
} from "@blueprintjs/core";
import "./map-caches.scss";
import { cacheModeAtom } from "../utils.ts";
import { useAtom } from "jotai";

export function CachePanelView({ data, dispatch }) {
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
    m(CacheList, { caches, dispatch }),
    m(CacheSystemControls, { dispatch, totalSize: data?.totalSize }),
  ]);
}

function CacheList({ caches, dispatch }: { caches: MapCacheListing[] }) {
  if (caches == null) {
    return m("div.cache-list-empty", m(Spinner));
  }

  if (caches.length == 0) {
    return m("div.cache-list-empty", m("div.ion-label", "No caches"));
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

function CacheItem({
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

  return m("div.ion-card.cache-card", { disabled: uiState == "deleting" }, [
    m("div.flex-row", [
      m("div.main-column", [
        m("div.ion-card-header", [
          m("h2.ion-card-subtitle", [
            isGlobal ? "Global" : (cache.description?.name ?? "Unnamed cache"),
          ]),
        ]),
        m("div.ion-card-content", [
          m(CacheLayers, { layers: cache.description?.layers }),
          m(CacheStatus, { cache }),
        ]),
        m(CacheControlActionButtons, {
          dispatch: interceptedDispatch,
          cacheId: cache.id,
          isDownloading,
        }),
      ]),
      m(_Map, {
        geometry: cache.definition.geometry,
        onClick() {
          dispatch({ type: "view", cacheId: cache.id });
        },
      }),
    ]),
  ]);
}

function LabeledControl({ label, children, inline = true }) {
  return m(FormGroup, { label, inline }, children);
}

type CacheUIState = "deleting" | "refreshing" | null;

function CacheSystemControls({
  totalSize,
  dispatch,
}: {
  totalSize: number;
  dispatch(action: CacheManagementAction): void;
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
            onClick: () => dispatch({ type: "delete-all" }),
          },
          "Delete all",
        ),
      ]),
      m(CacheModeControl),
    ]),
  ]);
}

function CacheModeControl() {
  const [cacheMode, setCacheMode] = useAtom(cacheModeAtom);
  return m(LabeledControl, { label: "Cache mode", inline: true }, [
    m(SegmentedControl, {
      size: "small",
      options: [
        { label: "Network", value: MapCachePriority.Network },
        {
          label: "Cache + Network",
          value: MapCachePriority.CacheThenNetwork,
        },
        { label: "Cache", value: MapCachePriority.Cache },
      ],
      onValueChange(value: MapCachePriority) {
        setCacheMode(value);
      },
      value: cacheMode,
    }),
  ]);
}

function CacheLayers({ layers }) {
  if (layers == null) return null;
  return m("div.cache-layers", [
    layers.map((layer) =>
      m("div.ion-chip", { key: layer }, [capitalize(layer), " "]),
    ),
  ]);
}

function CacheDownloadState({ data }: { data: OfflineRegionStatus }) {
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
    m.if(isDownloading)(CacheDownloadState, {
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
  return m(Button, { size: "small", icon, color, onClick, ...rest }, children);
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
