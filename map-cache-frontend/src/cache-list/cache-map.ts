import h from "@macrostrat/hyper";
import { forwardRef, useEffect, useRef, useState } from "react";
import { Map } from "mapbox-gl";
import { Settings } from "~/_models/settings";
import { baseMapStyles } from "~/components/map/map-style";
import { mergeStyles } from "@macrostrat/mapbox-utils";
import { boundsForPolygon } from "../map-cache.service";
import { useElementSize } from "@mantine/hooks";

function useOnScreen(ref, rootMargin = "0px") {
  // State and setter for storing whether element is visible
  const [isIntersecting, setIntersecting] = useState(false);

  useEffect(() => {
    const observer = new IntersectionObserver(
      ([entry]) => {
        // Update our state when observer callback fires
        setIntersecting(entry.isIntersecting);
      },
      {
        rootMargin,
      }
    );
    if (ref.current != null) {
      observer.observe(ref.current);
    }
    return () => {
      if (ref.current == null) return;
      observer.unobserve(ref.current);
    };
  }, []); // Empty array ensures that effect is only run on mount and unmount

  return isIntersecting;
}

function setupMap(
  el: HTMLDivElement,
  mapRef: React.MutableRefObject<Map>,
  data: GeoJSON.Polygon
) {
  if (el == null || data == null) return;

  el.style.width = "130px";
  el.style.height = "130px";

  let bounds = boundsForPolygon(data);

  const map = new Map({
    accessToken: Settings.MAPBOXAPIKEY,
    container: el,
    bounds,
    fitBoundsOptions: { padding: 20 },
    style: mergeStyles(baseMapStyles.basic, {
      sources: {
        cacheArea: {
          type: "geojson",
          data,
        },
      },
      layers: [
        {
          id: "polygon",
          type: "fill",
          source: "cacheArea", // reference the data source
          layout: {},
          paint: {
            "fill-color": "#0080ff", // blue color fill
            "fill-opacity": 0.2,
          },
        },
        // Add a black outline around the polygon.
        {
          id: "outline",
          type: "line",
          source: "cacheArea",
          layout: {},
          paint: {
            "line-color": "#000",
            "line-width": 3,
          },
        },
      ],
    }),
    // causes pan & zoom handlers not to be applied, similar to
    // .dragging.disable() and other handler .disable() funtions in Leaflet.
    interactive: false,
  });

  mapRef.current = map;
}

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
  ])
);

function buildStaticMapURL(data: any, { width, height }) {
  const bounds = boundsForPolygon(data);
  let url = `https://api.mapbox.com/styles/v1/jczaplewski/cl3w3bdai001f14ob27ckmpxz/static/`;
  url += `?access_token=${Settings.MAPBOXAPIKEY}&size=${width},${height}`;
  const feature = {
    geometry: data,
    type: "Feature",
    properties: {
      "fill-color": "#0080ff", // blue color fill
      "fill-opacity": 0.2,
      stroke: "#0080ff",
    },
  };
  return url + `&overlay=geojson(${JSON.stringify(feature)})`;
}

export function StaticCacheMap(props: {
  geometry: GeoJSON.Polygon;
  onClick: () => void;
}) {
  const src = buildStaticMapURL(props.geometry, { width: 130, height: 130 });
  return h(
    CacheMapContainer,
    {
      onClick: props.onClick,
    },
    [h("img", { src })]
  );
}

export function CacheMap({ geometry, onClick }) {
  if (geometry == null) return null;
  const mapRef = useRef<Map>(null);

  const { ref, width, height } = useElementSize();
  const isVisible = useOnScreen(ref);

  useEffect(() => {
    if (width == null || height == null) return;
    setupMap(ref.current, mapRef, geometry);
    return () => {
      if (mapRef.current != null) mapRef.current?.remove();
      mapRef.current = null;
    };
  }, [ref.current, width, height, isVisible]);

  return h(CacheMapContainer, { ref, onClick });
}
