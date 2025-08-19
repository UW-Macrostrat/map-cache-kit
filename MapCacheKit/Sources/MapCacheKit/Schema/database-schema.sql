create table regions (
    id INTEGER not null primary key autoincrement,
    definition TEXT not null,
    description BLOB,
    style TEXT,
    required_resource_count INTEGER
);

create unique index unique_style_url on regions (style);

create table resources (
    id INTEGER not null primary key autoincrement,
    url TEXT not null unique,
    kind INTEGER not null,
    expires INTEGER,
    modified INTEGER,
    etag TEXT,
    data BLOB,
    compressed INTEGER default 0 not null,
    accessed INTEGER not null,
    must_revalidate INTEGER default 0 not null
);

create table region_resources (
    region_id INTEGER not null references regions on delete cascade,
    resource_id INTEGER not null references resources,
    unique (region_id, resource_id)
);

create index region_resources_resource_id on region_resources (resource_id);

create index resources_accessed on resources (accessed);

create index resources_url on resources (url);

create table tiles (
    id INTEGER not null primary key autoincrement,
    url_template TEXT not null,
    pixel_ratio INTEGER not null,
    z INTEGER not null,
    x INTEGER not null,
    y INTEGER not null,
    expires INTEGER,
    modified INTEGER,
    etag TEXT,
    data BLOB,
    compressed INTEGER default 0 not null,
    accessed INTEGER not null,
    must_revalidate INTEGER default 0 not null,
    unique (url_template, pixel_ratio, z, x, y)
);

create table region_tiles (
    region_id INTEGER not null references regions on delete cascade,
    tile_id INTEGER not null references tiles,
    unique (region_id, tile_id)
);

create index region_tiles_tile_id on region_tiles (tile_id);

create index tiles_accessed on tiles (accessed);

create index tiles_url_template on tiles (url_template);
