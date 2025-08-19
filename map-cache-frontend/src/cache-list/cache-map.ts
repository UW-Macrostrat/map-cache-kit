import hyper from "@macrostrat/hyper";
import { forwardRef } from "react";
import { isGlobalCache } from "./utils";
import styles from "./map-caches.module.sass";
import type { MapCacheListing } from "./types.ts";
import { Icon } from "@blueprintjs/core";
import { cacheAPIBaseURL } from "../state.ts";

const h = hyper.styled(styles);

const CacheMapContainer: any = forwardRef((props, ref) =>
  h("div.cache-map-container", [
    h("div.cache-map", {
      ref,
      ...props,
      style: {
        width: "130px",
        height: "130px",
      },
    }),
  ]),
);

export function StaticCacheMap(props: {
  cache: MapCacheListing;
  size?: number;
  onClick: () => void;
}) {
  const { cache, size = 130 } = props;

  const width = size;
  const height = size;

  let src = null;
  if (!isGlobalCache(cache)) {
    src = cacheAPIBaseURL + `/regions/${cache.id}/thumbnail`;
  }

  let inner = null;
  if (src == null) {
    inner = h(Icon, { icon: "globe", size: 48 });
  } else {
    inner = h("img", { src, width, height });
  }

  return h(
    CacheMapContainer,
    {
      onClick: props.onClick,
    },
    inner,
  );
}
