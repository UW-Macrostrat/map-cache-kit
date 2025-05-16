SELECT geometry
FROM tile_cache.region
WHERE name = :region_name::text OR id = :region_name::integer;
