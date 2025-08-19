import satellite from "./style-jczaplewski-cl51esfdm000e14mq51erype3-satellite.json";
import basic from "./style-jczaplewski-cl3w3bdai001f14ob27ckmpxz-basic.json";

export interface MapSourceConfig {
  type?: string;
  tiles?: string[];
  tileSize?: number;
  data?: MapSourceConfigData;
  url?: string;
  cluster?: boolean;
  maxzoom?: number;
}

export interface MapSourceConfigData {
  type?: string;
  features?: any[];
}

// Base styles:
// Right now, these styles MUST include a `pin`, `pin-grey`, and `user-location` image.
// We're working on ways to bundle these images into the app at compile time, which would
// allow any style to be used.
// NOTE: we could directly use map styles from the web, but it'd be important to manage their
// caching properly, which we don't do so far.
export const baseMapStyles = {
  satellite,
  // Macrostrat rockd terrain v2
  basic,
};

export const mapStyleVersion = "1.0";

export const burwellSource = {
  type: "vector",
  tiles: ["https://tiles.macrostrat.org/carto/{z}/{x}/{y}.mvt"],
  tileSize: 512,
  maxzoom: 15,
};

export const Sources: { [k: string]: MapSourceConfig } = {
  terrain: {
    url: "mapbox://mapbox.terrain-rgb",
    type: "raster-dem",
    tileSize: 256,
    maxzoom: 15,
  },
  "mapbox://mapbox.terrain-rgb": {
    type: "raster-dem",
    url: "mapbox://mapbox.terrain-rgb",
    tileSize: 256,
    maxzoom: 15,
  },
  burwell: burwellSource,
  checkins: {
    type: "geojson",
    data: { type: "FeatureCollection", features: [] },
  },
  userLocation: {
    type: "geojson",
    data: {
      type: "FeatureCollection",
      features: [],
    },
  },
  "checkin-clusters": {
    type: "geojson",
    cluster: true,
    data: {
      type: "FeatureCollection",
      features: [],
    },
  },
  checkin: {
    type: "geojson",
    data: {
      type: "FeatureCollection",
      features: [],
    },
  },
  observations: {
    type: "geojson",
    data: {
      type: "FeatureCollection",
      features: [],
    },
  },
  "orig-location": {
    type: "geojson",
    data: {
      type: "FeatureCollection",
      features: [],
    },
  },
  "adjust-location": {
    type: "geojson",
    data: {
      type: "FeatureCollection",
      features: [],
    },
  },
  info_marker: {
    type: "geojson",
    data: {
      type: "FeatureCollection",
      features: [],
    },
  },
};

export const Layers = [
  {
    id: "burwell_fill",
    type: "fill",
    source: "burwell",
    "source-layer": "units",
    filter: ["!=", "color", ""],
    minzoom: 0,
    maxzoom: 16,
    paint: {
      "fill-color": {
        property: "color",
        type: "identity",
      },
      "fill-opacity": {
        stops: [
          [0, 0.5],
          [12, 0.3],
        ],
      },
    },
  },
  {
    id: "burwell_stroke",
    type: "line",
    source: "burwell",
    "source-layer": "units",
    filter: ["!=", "color", ""],
    minzoom: 0,
    maxzoom: 16,
    paint: {
      "line-color": "#777777",
      "line-width": 0,
      "line-opacity": {
        stops: [
          [0, 0],
          [4, 0.5],
        ],
      },
    },
  },
  {
    id: "burwell_water_fill",
    type: "fill",
    source: "burwell",
    "source-layer": "units",
    filter: ["==", "color", ""],
    minzoom: 0,
    maxzoom: 16,
    paint: {
      "fill-opacity": 0,
    },
  },
  {
    id: "burwell_water_line",
    type: "line",
    source: "burwell",
    "source-layer": "units",
    filter: ["==", "color", ""],
    minzoom: 0,
    maxzoom: 16,
    paint: {
      "line-opacity": 0,
      "line-width": 1,
    },
  },
  {
    id: "invisible_lines",
    type: "line",
    source: "burwell",
    "source-layer": "lines",
    minzoom: 0,
    maxzoom: 16,
    paint: {
      "line-opacity": 0,
    },
  },
  {
    id: "faults",
    type: "line",
    source: "burwell",
    "source-layer": "lines",
    filter: [
      "in",
      "type",
      "fault",
      "normal fault",
      "thrust fault",
      "strike-slip fault",
      "reverse fault",
      "growth fault",
      "fault zone",
      "zone",
    ],
    minzoom: 0,
    maxzoom: 16,
    paint: {
      "line-color": "#000000",
      "line-width": {
        stops: [
          [0, 0.3],
          [1, 0.3],
          [2, 0.3],
          [3, 0.3],
          [4, 0.5],
          [5, 0.6],
          [6, 0.45],
          [7, 0.4],
          [8, 0.7],
          [9, 0.8],
          [10, 0.7],
          [11, 1.1],
          [12, 1.3],
          [13, 1.5],
          [14, 1.6],
          [15, 1.75],
          [16, 2.2],
        ],
      },
      "line-opacity": 1,
    },
  },
  {
    id: "moraines",
    type: "line",
    source: "burwell",
    "source-layer": "lines",
    filter: ["==", "type", "moraine"],
    minzoom: 12,
    maxzoom: 16,
    layout: {
      "line-join": "round",
      "line-cap": "round",
    },
    paint: {
      "line-color": "#3498DB",
      "line-dasharray": [1, 2],
      "line-width": {
        stops: [
          [10, 1],
          [11, 2],
          [12, 2],
          [13, 2.5],
          [14, 3],
          [15, 3],
        ],
      },
      "line-opacity": {
        stops: [
          [10, 0.2],
          [13, 1],
        ],
      },
    },
  },
  {
    id: "eskers",
    type: "line",
    source: "burwell",
    "source-layer": "lines",
    filter: ["==", "type", "esker"],
    minzoom: 12,
    maxzoom: 16,
    layout: {
      "line-join": "round",
      "line-cap": "round",
    },
    paint: {
      "line-color": "#00FFFF",
      "line-dasharray": [1, 4],
      "line-width": {
        stops: [
          [10, 1],
          [11, 2],
          [12, 2],
          [13, 2.5],
          [14, 3],
          [15, 3],
        ],
      },
      "line-opacity": {
        stops: [
          [10, 0.2],
          [13, 1],
        ],
      },
    },
  },
  {
    id: "lineaments",
    type: "line",
    source: "burwell",
    "source-layer": "lines",
    filter: ["==", "type", "lineament"],
    minzoom: 0,
    maxzoom: 16,
    layout: {
      "line-join": "round",
      "line-cap": "round",
    },
    paint: {
      "line-color": "#000000",
      "line-dasharray": [2, 2, 7, 2],
      "line-width": {
        stops: [
          [9, 1],
          [10, 1],
          [11, 2],
          [12, 2],
          [13, 2.5],
          [14, 3],
          [15, 3],
        ],
      },
      "line-opacity": 1,
    },
  },
  {
    id: "synclines",
    type: "line",
    source: "burwell",
    "source-layer": "lines",
    filter: ["==", "type", "syncline"],
    minzoom: 0,
    maxzoom: 16,
    layout: {
      "line-join": "round",
      "line-cap": "round",
    },
    paint: {
      "line-color": "#F012BE",
      "line-width": {
        stops: [
          [0, 1],
          [7, 0.25],
          [8, 0.4],
          [9, 0.45],
          [10, 0.45],
          [11, 0.6],
          [12, 0.7],
          [13, 0.9],
          [14, 1.4],
          [15, 1.75],
          [16, 2.2],
        ],
      },
      "line-opacity": 1,
    },
  },
  {
    id: "monoclines",
    type: "line",
    source: "burwell",
    "source-layer": "lines",
    filter: ["==", "type", "monocline"],
    minzoom: 0,
    maxzoom: 16,
    layout: {
      "line-join": "round",
      "line-cap": "round",
    },
    paint: {
      "line-color": "#F012BE",
      "line-width": {
        stops: [
          [0, 1],
          [7, 0.25],
          [8, 0.4],
          [9, 0.45],
          [10, 0.45],
          [11, 0.6],
          [12, 0.7],
          [13, 0.9],
          [14, 1.4],
          [15, 1.75],
          [16, 2.2],
        ],
      },
      "line-opacity": 1,
    },
  },
  {
    id: "folds",
    type: "line",
    source: "burwell",
    "source-layer": "lines",
    filter: ["==", "type", "fold"],
    minzoom: 0,
    maxzoom: 16,
    layout: {
      "line-join": "round",
      "line-cap": "round",
    },
    paint: {
      "line-color": "#F012BE",
      "line-width": {
        stops: [
          [0, 1],
          [7, 0.25],
          [8, 0.4],
          [9, 0.45],
          [10, 0.45],
          [11, 0.6],
          [12, 0.7],
          [13, 0.9],
          [14, 1.4],
          [15, 1.75],
          [16, 2.2],
        ],
      },
      "line-opacity": 1,
    },
  },
  {
    id: "dikes",
    type: "line",
    source: "burwell",
    "source-layer": "lines",
    filter: ["==", "type", "dike"],
    minzoom: 6,
    maxzoom: 16,
    layout: {
      "line-join": "round",
      "line-cap": "round",
    },
    paint: {
      "line-color": "#FF4136",
      "line-width": {
        stops: [
          [0, 1],
          [7, 0.25],
          [8, 0.4],
          [9, 0.45],
          [10, 0.45],
          [11, 0.6],
          [12, 0.7],
          [13, 0.9],
          [14, 1.4],
          [15, 1.75],
          [16, 2.2],
        ],
      },
      "line-opacity": {
        stops: [
          [6, 0.2],
          [10, 1],
        ],
      },
    },
  },
  {
    id: "anticlines",
    type: "line",
    source: "burwell",
    "source-layer": "lines",
    filter: ["==", "type", "anticline"],
    minzoom: 0,
    maxzoom: 16,
    layout: {
      "line-join": "round",
      "line-cap": "round",
    },
    paint: {
      "line-color": "#F012BE",
      "line-width": {
        stops: [
          [0, 1],
          [7, 0.25],
          [8, 0.4],
          [9, 0.45],
          [10, 0.45],
          [11, 0.6],
          [12, 0.7],
          [13, 0.9],
          [14, 1.4],
          [15, 1.75],
          [16, 2.2],
        ],
      },
      "line-opacity": 1,
    },
  },
  {
    id: "flows",
    type: "line",
    source: "burwell",
    "source-layer": "lines",
    filter: ["==", "type", "flow"],
    minzoom: 0,
    maxzoom: 16,
    layout: {
      "line-join": "round",
      "line-cap": "round",
    },
    paint: {
      "line-color": "#FF4136",
      "line-width": {
        stops: [
          [0, 1],
          [7, 0.25],
          [8, 0.4],
          [9, 0.45],
          [10, 0.45],
          [11, 0.6],
          [12, 0.7],
          [13, 0.9],
          [14, 1.4],
          [15, 1.75],
          [16, 2.2],
        ],
      },
      "line-opacity": 1,
    },
  },
  {
    id: "sills",
    type: "line",
    source: "burwell",
    "source-layer": "lines",
    filter: ["==", "type", "sill"],
    minzoom: 0,
    maxzoom: 16,
    layout: {
      "line-join": "round",
      "line-cap": "round",
    },
    paint: {
      "line-color": "#FF4136",
      "line-width": {
        stops: [
          [0, 1],
          [7, 0.25],
          [8, 0.4],
          [9, 0.45],
          [10, 0.45],
          [11, 0.6],
          [12, 0.7],
          [13, 0.9],
          [14, 1.4],
          [15, 1.75],
          [16, 2.2],
        ],
      },
      "line-opacity": 1,
    },
  },
  {
    id: "veins",
    type: "line",
    source: "burwell",
    "source-layer": "lines",
    filter: ["==", "type", "vein"],
    minzoom: 0,
    maxzoom: 16,
    layout: {
      "line-join": "round",
      "line-cap": "round",
    },
    paint: {
      "line-color": "#FF4136",
      "line-width": {
        stops: [
          [0, 1],
          [7, 0.25],
          [8, 0.4],
          [9, 0.45],
          [10, 0.45],
          [11, 0.6],
          [12, 0.7],
          [13, 0.9],
          [14, 1.4],
          [15, 1.75],
          [16, 2.2],
        ],
      },
      "line-opacity": {
        stops: [
          [6, 0.2],
          [10, 1],
        ],
      },
    },
  },
  {
    id: "marker_beds",
    type: "line",
    source: "burwell",
    "source-layer": "lines",
    filter: ["in", "type", "marker bed", "bed"],
    minzoom: 12,
    maxzoom: 16,
    layout: {
      "line-join": "round",
      "line-cap": "round",
    },
    paint: {
      "line-color": "#333333",
      "line-width": {
        stops: [
          [10, 0.8],
          [11, 0.8],
          [12, 0.9],
          [13, 0.9],
          [14, 1.4],
          [15, 1.75],
          [16, 2.2],
        ],
      },
      "line-opacity": 1,
    },
  },
  {
    id: "craters",
    type: "line",
    source: "burwell",
    "source-layer": "lines",
    filter: ["in", "type", "crater", "impact structure"],
    minzoom: 10,
    maxzoom: 16,
    paint: {
      "line-dasharray": [6, 6],
      "line-color": "#000000",
      "line-width": {
        stops: [
          [10, 0.6],
          [11, 0.6],
          [12, 0.72],
          [13, 0.72],
          [14, 1],
          [15, 1.3],
          [16, 1.8],
        ],
      },
      "line-opacity": 1,
    },
  },
];

export const geologyStyleFragment = {
  sources: Sources,
  layers: Layers,
  version: 8 as 8,
  name: "rockd-geology",
};
