import m from "@macrostrat/hyper";
import type {
  CacheRegionProgress,
  MapCacheListing,
  ResourceInfo,
} from "./types";
import { MapCachePriority } from "./types";
import { CacheMap } from "./cache-map";
import { memo } from "react";
import { findGlobalCache, isGlobalCache, isStyleCache } from "./utils";
import {
  Button,
  Card,
  FormGroup,
  Intent,
  ProgressBar,
  SegmentedControl,
  Spinner,
  Switch,
} from "@blueprintjs/core";
import "./map-caches.scss";
import {
  cacheModeAtom,
  cacheDataAtom,
  mapAtom,
  showCacheFormAtom,
  newCacheDataAtom,
  cacheLayersAtom,
  useDownloadProgress,
  createGlobalCache,
  deleteCache,
  deleteAllCaches,
  createCache,
} from "../state.ts";
import { useAtom } from "jotai";
import { bbox } from "@turf/bbox";
import type { LngLatBoundsLike } from "mapbox-gl";
import { OverlayToaster } from "@blueprintjs/core";
import { createRoot } from "react-dom/client";

const Toaster = await OverlayToaster.createAsync(
  {},
  {
    domRenderer: (toaster, containerElement) =>
      createRoot(containerElement).render(toaster),
  },
);

export function CachePanelView() {
  const [data] = useAtom(cacheDataAtom);
  if (data == null) {
    return m("div.cache-list-panel", m(Spinner));
  }

  const caches = data.regions ?? [];
  let _caches = caches.filter((c) => !isStyleCache(c));
  _caches.reverse();
  const totalSize = data.assets.tile_size + data.assets.resource_size;
  const hasGlobalCache = findGlobalCache(_caches) != null;

  return m("div.cache-list-panel", [
    m.if(!hasGlobalCache)(AddGlobalCacheButton),
    m(NewCacheForm),
    m(CacheList, { caches: _caches }),
    m(CacheSystemControls, { totalSize }),
  ]);
}

function CacheList({ caches }: { caches: MapCacheListing[] }) {
  if (caches.length == 0) {
    return m("div.cache-list-empty", m("div.ion-label", "No caches"));
  }

  return m([
    m(
      "div.ion-list",
      null,
      caches.map((cache) => {
        return m(CacheItem, {
          key: cache.id,
          cache,
        });
      }),
    ),
    m("div.cache-list-spacer"),
  ]);
}

function NewCacheForm() {
  const [showForm, setShowForm] = useAtom(showCacheFormAtom);
  const [cacheData] = useAtom(newCacheDataAtom);
  const [cacheLayers, setCacheLayers] = useAtom(cacheLayersAtom);

  if (!showForm) {
    return m(
      Button,
      {
        icon: "add",
        onClick: () => setShowForm(true),
        className: "ion-margin",
      },
      "Create new cache",
    );
  }

  return m(Card, [
    m("h3", cacheData.name),
    m(LabeledControl, { label: "Layers" }, [
      m("div.cache-layers-checkboxes", [
        ["bedrock", "basemap", "satellite"].map((layer) =>
          m(Switch, {
            type: "checkbox",
            label: capitalize(layer),
            checked: cacheLayers[layer],
            onChange: (e) => {
              setCacheLayers((val) => {
                return {
                  ...val,
                  [layer]: e.target.checked,
                };
              });
            },
          }),
        ),
      ]),
    ]),
    m(
      Button,
      {
        icon: "check",
        intent: "primary",
        onClick: clickHandler(createCache),
      },
      "Create cache",
    ),
    m(
      Button,
      {
        icon: "cross",
        intent: "danger",
        onClick() {
          setShowForm(false);
        },
      },
      "Cancel",
    ),
  ]);
}

const _Map = memo(CacheMap);

function CacheItem({ cache }: { cache: MapCacheListing }) {
  const downloadStatus = useDownloadProgress(cache.id);
  const progress = downloadStatus?.progress ?? 1;
  const isDownloading = progress < 1;

  const isGlobal = isGlobalCache(cache);

  const [map] = useAtom(mapAtom);

  const onClick = () => {
    if (map == null) return;
    const bounds = bbox(cache.definition.geometry);
    const _bbox: LngLatBoundsLike = [
      [bounds[0], bounds[1]],
      [bounds[2], bounds[3]],
    ];
    map.fitBounds(_bbox, { duration: 500 });
  };

  return m("div.ion-card.cache-card", [
    m("div.flex-row", [
      m("div.main-column", [
        m("div.ion-card-header", [
          m("h2.ion-card-subtitle", [
            isGlobal ? "Global" : (cache.description?.name ?? "Unnamed cache"),
          ]),
        ]),
        m("div.ion-card-content", [
          m(CacheLayers, { layers: cache.description?.layers }),
          m(CacheZoomLevels, { cache }),
          m("div.cache-status", [
            m.if(isDownloading)(ProgressBar, {
              value: progress,
              stripes: false,
              intent:
                (downloadStatus?.hasErrors ?? false)
                  ? Intent.WARNING
                  : Intent.PRIMARY,
            }),
            m("p.flex-row", [
              m(CacheSizes, {
                ...getBestResourceInfo(cache.assets, downloadStatus),
              }),
              m("span.spacer"),
              m.if(!isDownloading)(CacheDateBlock, { cache }),
            ]),
          ]),
        ]),
        m(CacheControlActionButtons, {
          cacheId: cache.id,
        }),
      ]),
      m(_Map, {
        geometry: cache.definition.geometry,
        onClick,
      }),
    ]),
  ]);
}

function CacheZoomLevels({ cache }: { cache: MapCacheListing }) {
  const minZoom = cache.definition.min_zoom;
  const maxZoom = cache.definition.max_zoom;

  return m("div.cache-zoom-levels", [
    m("strong", "Zoom levels: "),
    minZoom,
    " - ",
    maxZoom,
  ]);
}

function LabeledControl({ label, children, inline = true }) {
  return m(FormGroup, { label, inline }, children);
}

type CacheUIState = "deleting" | "refreshing" | null;

function CacheSystemControls({
  totalSize,
}: {
  totalSize: number;
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
            intent: "danger",
            onClick: clickHandler(deleteAllCaches),
          },
          "Delete all",
        ),
      ]),
      m(CacheModeControl),
    ]),
  ]);
}

export function CacheModeControl({ inline = false }) {
  const [cacheMode, setCacheMode] = useAtom(cacheModeAtom);
  return m(LabeledControl, { label: "Cache mode", inline }, [
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
  return m("ul.cache-layers", [
    layers.map((layer) => m("li", { key: layer }, capitalize(layer))),
  ]);
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

function CacheControlActionButtons({ cacheId }) {
  return m("div.ion-row", { class: "ion-padding-start" }, [
    m(
      IconButton,
      {
        icon: "trash",
        intent: "danger",
        onClick: clickHandler(() => deleteCache(cacheId)),
      },
      "Delete",
    ),
  ]);
}

function AddGlobalCacheButton() {
  return m(
    IconButton,
    {
      intent: "success",
      icon: "globe",
      onClick: clickHandler(createGlobalCache),
    },
    "Create global cache",
  );
}

function clickHandler(action: () => Promise<void>) {
  return async () => {
    try {
      await action();
    } catch (e) {
      let message = "An error occurred while performing the action.";
      if (e instanceof Error) {
        message = e.message;
      } else if (typeof e === "string") {
        message = e;
      }

      Toaster.show({
        message,
        intent: Intent.DANGER,
      });
      console.error("Error performing action", message);
    }
  };
}

function IconButton({ icon, onClick, color, children, ...rest }) {
  return m(Button, { size: "small", icon, color, onClick, ...rest }, children);
}

function getBestResourceInfo(
  assets: ResourceInfo | null,
  status: CacheRegionProgress | null,
): ResourceInfo | null {
  if (status != null) {
    return {
      tile_count: status.tilesDownloaded + status.tilesInitiallyDownloaded,
      tile_size: status.tilesDownloadedSize, // Tile size is not provided in the status
      resource_count:
        status.resourcesDownloaded + status.resourcesInitiallyDownloaded,
      resource_size: status.resourcesDownloadedSize, // Resource size is not provided in the status
      expected_tile_count: status.tilesTotal,
    };
  }
  if (assets != null) {
    return assets;
  }
  return null;
}

function CacheSizes({
  tile_size,
  resource_size,
  tile_count,
  expected_tile_count = null,
  expanded = false,
}: ResourceInfo & { expected_tile_count?: number | null; expanded?: boolean }) {
  const totalSize = tile_size + resource_size;
  return m("span.cache-sizes", [
    m(CacheSize, { size: totalSize }),
    m.if(expanded)([
      " (",
      m(CacheSize, { size: tile_size }),
      " tiles and ",
      m(CacheSize, { size: resource_size }),
      " resources)",
    ]),
    ", ",
    tile_count,
    m.if(expected_tile_count != null)([" of ", expected_tile_count]),
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
