# Rockd-map-cache-v1.db

This database was created by the Rockd app v3, using the first
version of the map caching system that was powered by Mapbox
GL Native bindings.

Version 2 of the map cache inherits the basic database structure
from this version, but is designed to be more flexible and
not necessarily tied to Mapbox.

To create the test fixture, we subset the database by removing
all font stacks for ranges greater than 0-255.pbf
(fonts to code points as great as 65535). This removed about 14 MB of compressed data.
Now there are only 1 MB of resources left.

```sql
DELETE FROM resources WHERE kind = 4 AND url NOT LIKE '%0-255.pbf';

SELECT sum(length(data)) FROM resources;

SELECT sum(length(data))/1024/1024, count(*) FROM tiles WHERE z < 3;

DELETE FROM tiles WHERE z > 1;

SELECT tile_id FROM region_tiles WHERE tile_id NOT IN (SELECT id FROM tiles);

DELETE FROM region_tiles WHERE tile_id NOT IN (SELECT id FROM tiles);

DELETE FROM region_resources WHERE resource_id NOT IN (SELECT id FROM resources);
```
