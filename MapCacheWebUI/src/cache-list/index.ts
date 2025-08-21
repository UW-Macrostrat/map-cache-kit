import hyper from "@macrostrat/hyper";
import type {
  CacheRegionProgress,
  MapCacheListing,
  ResourceInfo,
} from "./types";
import { StaticCacheMap } from "./cache-map";
import { memo } from "react";
import { findGlobalCache, isGlobalCache, isStyleCache } from "./utils";
import {
  Button,
  ButtonGroup,
  Card,
  FormGroup,
  InputGroup,
  Intent,
  NonIdealState,
  ProgressBar,
  Spinner,
  Switch,
} from "@blueprintjs/core";
import styles from "./map-caches.module.sass";
import {
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
  setRegionName,
  refreshDefinitions,
} from "../state.ts";
import { useAtom, useSetAtom } from "jotai";
import { bbox } from "@turf/bbox";
import type { LngLatBoundsLike } from "mapbox-gl";
import { OverlayToaster } from "@blueprintjs/core";
import { createRoot } from "react-dom/client";

const m = hyper.styled(styles);

const Toaster = await OverlayToaster.createAsync(
  {},
  {
    domRenderer: (toaster, containerElement) =>
      createRoot(containerElement).render(toaster),
  },
);

export function CachePanelView() {
  const [showForm, setShowForm] = useAtom(showCacheFormAtom);
  const [data] = useAtom(cacheDataAtom);
  if (data == null) {
    return m("div.cache-list-panel", m(Spinner));
  }

  const caches = data.regions ?? [];
  let _caches = caches.filter((c) => !isStyleCache(c));
  _caches.reverse();
  const totalSize = data.assets.tile_size + data.assets.resource_size;
  const hasGlobalCache = findGlobalCache(_caches) != null;

  const hasMaxAllowedCaches = _caches.length >= data.maxNumberOfRegions;

  let topElement = m(ButtonGroup, { vertical: true, large: true }, [
    m.if(!hasGlobalCache)(AddGlobalCacheButton),
    m(
      Button,
      {
        icon: "add",
        onClick: () => setShowForm(true),
        className: "ion-margin",
        intent: "primary",
        disabled: hasMaxAllowedCaches,
      },
      "Create new cache",
    ),
  ]);

  if (showForm) {
    topElement = m(NewCacheForm);
  }

  return m("div.cache-list-panel", [
    topElement,
    m(CacheList, {
      caches: _caches,
      maxNumberOfRegions: data.maxNumberOfRegions,
    }),
    m(CacheSystemControls, { totalSize }),
  ]);
}

function CacheList({
  caches,
  maxNumberOfRegions = Infinity,
}: {
  caches: MapCacheListing[];
  maxNumberOfRegions?: number;
}) {
  if (caches.length == 0) {
    return m(NonIdealState, {
      icon: "layers",
      title: "No caches found",
    });
  }

  let footer = null;
  let cachesCount = null;
  const nRemaining = (maxNumberOfRegions ?? Infinity) - caches.length;
  if (nRemaining <= 0) {
    cachesCount = "Maximum number of regions reached.";
  } else if (nRemaining < Infinity) {
    cachesCount = `You can cache ${nRemaining} more region${nRemaining > 1 ? "s" : ""}.`;
  }
  if (cachesCount != null) {
    footer = m("p.cache-list-info", cachesCount);
  }

  return m([
    footer,
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
  ]);
}

function NewCacheForm() {
  const [cacheData] = useAtom(newCacheDataAtom);
  const [cacheLayers, setCacheLayers] = useAtom(cacheLayersAtom);
  const setShowForm = useSetAtom(showCacheFormAtom);

  return m(Card, [
    m(InputGroup, {
      value: cacheData.name,
      onValueChange(value) {
        setRegionName(value);
      },
    }),
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
    m(ButtonGroup, [
      m(
        Button,
        {
          icon: "map-create",
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
    ]),
  ]);
}


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

  return m(CacheCard, { className: "cache-item" }, [
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
      m(StaticCacheMap, {
        cache,
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
  return m(CacheCard, [
    m("div.flex-row", [
      m(FormGroup, { label: "Total size", inline: true }, [
        m(CacheSize, { size: totalSize }),
      ]),
      m("div.spacer"),
      m(ButtonGroup, { size: "small", minimal: true }, [
        m(
          Button,
          {
            icon: "refresh",
            intent: "warning",
            onClick: clickHandler(refreshDefinitions),
          },
          "Refresh",
        ),
        m(
          Button,
          {
            icon: "trash",
            intent: "danger",
            onClick: clickHandler(deleteAllCaches),
          },
          "Delete all",
        ),
      ]),
    ]),
  ]);
}

function CacheCard({ children, className }) {
  return m("div.bp5-card.minimal-card", { className }, [
    m("div.ion-card-content", children),
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
      Button,
      {
        icon: "trash",
        intent: "danger",
        size: "small",
        onClick: clickHandler(() => deleteCache(cacheId)),
      },
      "Delete",
    ),
  ]);
}

function AddGlobalCacheButton() {
  return m(
    Button,
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
