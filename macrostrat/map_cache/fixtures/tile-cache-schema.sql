/**
  Tile cache schema for storing map tiles from a variety of sources.
  Originally based on Macrostrat's L2 tile cache, found here:
    https://githib.com/UW-Macrostrat/postgis-tile-utils

  The goal is to have a schema design that can work in SQLite or PostGIS,
  and support a variety of caching tasks.
 */

CREATE SCHEMA tile_cache;

CREATE TABLE IF NOT EXISTS tile_cache.profile (
      id serial PRIMARY KEY,
      name text NOT NULL UNIQUE,
      format text NOT NULL,
      content_type text NOT NULL,
      minzoom integer,
      maxzoom integer
);

CREATE TABLE IF NOT EXISTS tile_cache.tile (
  x integer NOT NULL,
  y integer NOT NULL,
  z integer NOT NULL,
  profile integer NOT NULL REFERENCES tile_cache.profile(id),
  -- For speed, we reduce the hash to an integer, increasing the likelihood of collisions
  -- but reducing the size of the index and efficiency of querying over it. This could be
  -- revisited if hash collisions become a problem, but they will only be important in edge
  -- cases where the same tile is requested with different parameters.
  -- We could also just index the parameters themselves (right now it's just t_step for paleogeography).
  args_hash integer NOT NULL,
  created timestamp without time zone NOT NULL DEFAULT now(),
  last_used timestamp without time zone NOT NULL DEFAULT now(),
  /* TODO: we could cache each layer separately and merge in the tile server */
  --layers text[] NOT NULL,
  tile bytea NOT NULL,
  PRIMARY KEY (x, y, z, profile, args_hash),
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
  profile,
  args_hash,
  length(tile) tile_size,
  created,
  last_used
FROM tile_cache.tile;
