CREATE EXTENSION IF NOT EXISTS postgis;
CREATE SCHEMA IF NOT EXISTS tile_cache;
SET SEARCH_PATH TO tile_cache, public;


CREATE TABLE IF NOT EXISTS tile_cache.region (
  id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name text NOT NULL,
  geometry Geometry(MultiPolygon, 4326) NOT NULL,
  min_zoom integer,
  max_zoom integer
);
