INSERT INTO tile_cache.layer (name, url_pattern, format, content_type)
VALUES ('mapbox-terrain-dem',
        'https://api.mapbox.com/raster/v1/mapbox.mapbox-terrain-dem-v1/{z}/{x}/{y}.png',
        'png',
        'image/png'),
       ('mapbox-streets-v8',
        'https://api.mapbox.com/v4/mapbox.mapbox-streets-v8/{z}/{x}/{y}.vector.pbf', 'mvt',
        'application/vnd.mapbox-vector-tile'),
       ('mapbox-terrain-v2',
        'https://api.mapbox.com/v4/mapbox.mapbox-terrain-v2/{z}/{x}/{y}.vector.pbf', 'mvt',
        'application/vnd.mapbox-vector-tile'),
       ('mapbox-bathymetry-v2',
        'https://api.mapbox.com/v4/mapbox.mapbox-bathymetry-v2/{z}/{x}/{y}.vector.pbf', 'mvt',
        'application/vnd.mapbox-vector-tile'),
       ('mapbox-satellite', 'https://api.mapbox.com/v4/mapbox.satellite/{z}/{x}/{y}@2x.png', 'png', 'image/png')
ON CONFLICT (name) DO NOTHING;
