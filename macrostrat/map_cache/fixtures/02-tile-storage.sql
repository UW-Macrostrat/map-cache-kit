/**
  Tile cache schema for storing map tiles from a variety of sources.
  Originally based on Macrostrat's L2 tile cache, found here:
    https://githib.com/UW-Macrostrat/postgis-tile-utils

  The goal is to have a schema design that can work in SQLite or PostGIS,
  and support a variety of caching tasks.
 */

CREATE TABLE IF NOT EXISTS tile_cache.layer (
      id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      name text NOT NULL UNIQUE,
      url_pattern text NOT NULL,
      format text NOT NULL,
      content_type text NOT NULL,
      min_zoom integer,
      max_zoom integer,
      tilejson jsonb
);

CREATE TABLE IF NOT EXISTS tile_cache.tile (
  x integer NOT NULL,
  y integer NOT NULL,
  z integer NOT NULL,
  layer integer NOT NULL REFERENCES tile_cache.layer(id),
  created timestamp without time zone NOT NULL DEFAULT now(),
  last_used timestamp without time zone NOT NULL DEFAULT now(),
  /* TODO: we could cache each layer separately and merge in the tile server */
  --layers text[] NOT NULL,
  data bytea NOT NULL,
  PRIMARY KEY (x, y, z, layer),
  -- Make sure tile is within TMS bounds
  CHECK (x >= 0 AND y >= 0 AND z >= 0 AND x < 2^z AND y < 2^z)
);
/* We'll need to add a TMS column if we want to support non-mercator tiles */


CREATE INDEX IF NOT EXISTS tile_cache_tile_last_used_idx ON tile_cache.tile (last_used);

/* A view to show info about cached tiles */
CREATE OR REPLACE VIEW tile_cache.tile_info AS
SELECT
  x,
  y,
  z,
  layer,
  length(data) tile_size,
  created,
  last_used
FROM tile_cache.tile;
