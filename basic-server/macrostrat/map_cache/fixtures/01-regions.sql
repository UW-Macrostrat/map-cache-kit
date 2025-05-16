CREATE EXTENSION IF NOT EXISTS postgis;
CREATE SCHEMA IF NOT EXISTS tile_cache;
SET SEARCH_PATH TO tile_cache, public;


CREATE TABLE IF NOT EXISTS tile_cache.region (
  id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name text NOT NULL UNIQUE,
  geometry Geometry(MultiPolygon, 4326) NOT NULL,
  min_zoom integer,
  max_zoom integer
);


INSERT INTO tile_cache.region (name, geometry, min_zoom, max_zoom)
VALUES ('world', ST_MakeEnvelope(-180, -85, 180, 85, 4326), 0, 5)
ON CONFLICT (name) DO NOTHING;
