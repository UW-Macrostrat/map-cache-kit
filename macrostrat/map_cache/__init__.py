from http.client import HTTPException
import asyncio
from asyncio import gather,  sleep, run
import httpx

from typer import Typer
from macrostrat.database import Database
from dotenv import load_dotenv
from os import environ
from pathlib import Path
from rich import print
import morecantile
from morecantile import Tile
from httpx import get, AsyncClient
from random import uniform
from urllib import parse
from typer import Option
import json

load_dotenv()

db = Database(environ["MAP_CACHE_DATABASE_URL"])

mapbox_token = environ["MAPBOX_API_TOKEN"]

cli = Typer()

__here__ = Path(__file__).parent


@cli.command()
def create():
    db.run_fixtures(__here__ / "fixtures")
    db.run_fixtures(__here__ / "fixtures" / "03-tile-utils")


@cli.command()
def regions():
    res = db.run_query("SELECT id, name FROM tile_cache.region").fetchall()
    for row in res:
        _print_info(row)

tms = morecantile.tms.get("WebMercatorQuad")

@cli.command("region")
def get_region(name: str, *, max_zoom: int = None, download: bool = False, layer: list[str] = None):
    id = None
    if name.isdigit():
        id = int(name)
        name = None

    res = db.run_query("SELECT id, name, min_zoom, max_zoom FROM tile_cache.region WHERE name = :name OR id = :id",
                       dict(name=name, id=id)
    ).one()

    _print_info(res)

    parent = get_parent_tile(res.id)

    min_zoom = res.min_zoom
    if min_zoom is None:
        min_zoom = parent.z
    if max_zoom is None:
        max_zoom = res.max_zoom
    if max_zoom is None:
        max_zoom = min(parent.z+5, 18)

    _print_val("Parent tile", parent)
    _print_val("Zoom range", f"{min_zoom}-{max_zoom}")

    dz = max_zoom - min_zoom
    n_tiles = len(list(tile_iterator(parent, min_zoom, max_zoom)))
    _print_val("Tiles per layer", n_tiles)

    if not download:
        return

    run(get_all_layers(parent, min_zoom, max_zoom, layer))

@cli.command("info")
def get_size():
    layers = db.run_query("SELECT id, name, url_pattern, format FROM tile_cache.layer").fetchall()
    print("Layers:")
    for layer in layers:
        print(f"{layer.name} ({layer.format})")


    res = db.run_query("""
    SELECT count(*) n_tiles, sum(length(data)) total_size FROM tile_cache.tile
    """).one()
    _print_val("Number of tiles", res.n_tiles)
    _print_val("Total size", f"{res.total_size/1024/1024:.2f} MB")

# Download layers in parallel

@cli.command("files")
def get_files(urls: list[str] = None, download: bool = False, url_list: Path = Option(None, "--url-list", help="Path to a file with a list of URLs")):
    """Get arbitrary files and save them to the database."""
    if urls is None:
        urls = []

    if url_list is not None:
        with url_list.open() as f:
            urls.extend(f.readlines())

    if not download:
        return

    run(download_files(urls))

async def download_files(urls):
    async with httpx.AsyncClient(limits=httpx.Limits(max_connections=8)) as client:
        tasks = []
        for url in urls:
            task = asyncio.create_task(download_file(client, url))
            tasks.append(task)
        await gather(*tasks)


async def download_file(client, url):
    # Strip off query parameters
    split_url = parse.urlsplit(url)
    # Remove query string and replace with mapbox token
    qs = "access_token=" + mapbox_token
    url = parse.urlunsplit((split_url.scheme, split_url.netloc, split_url.path, qs, ""))

    res = db.run_query("SELECT 1 FROM tile_cache.file WHERE url = :url", dict(url=url)).fetchone()
    print(url, end="")
    if res is not None:
        print(f"...already present")
        return

    res = await client.get(url)
    print(f"...{res.status_code}")

    data = res.content

    content_type = res.headers["Content-Type"]

    db.run_sql("""
        INSERT INTO tile_cache.file (url, data, json_data, content_type, format, compressed, hash)
        VALUES (:url, :data, :json_data, :content_type, :format, :compressed, md5(:data)::uuid)
        """,
        dict(
            url=url,
            data=data,
            content_type=content_type,
            compressed=_is_zipped(data),
            json_data=get_json(res),
            format=infer_format(url, data, content_type),

        )
    )
    db.session.commit()

def get_json(req):
    try:
        return json.dumps(req.json())
    except ValueError:
        return None

def infer_format(url, data, content_type):
    """Infer the format of the file."""
    if content_type == "application/json":
        return "json"
    if content_type == "application/vnd.mapbox-vector-tile":
        return "mvt"
    if content_type == "image/png":
        return "png"
    if content_type == "image/jpeg":
        return "jpeg"
    if content_type == "image/webp":
        return "webp"
    if content_type == "application/x-protobuf":
        return "pbf"




# Download layers in parallel

async def get_all_layers(parent, min_zoom, max_zoom, _layers):
    layers = db.run_query("SELECT id, name, url_pattern, format FROM tile_cache.layer").fetchall()
    if _layers is not None:
        # Filter layers if specified
        layers = [layer for layer in layers if layer.name in _layers]
    async with httpx.AsyncClient(limits=httpx.Limits(max_connections=8)) as client:
        tasks = []

        for layer in layers:
            task = asyncio.create_task(download_layer(client, parent, layer, min_zoom, max_zoom))
            tasks.append(task)

        await gather(*tasks)

async def download_layer(client, parent, layer, min_zoom, max_zoom):
    print("Downloading layer", layer.name)

    tiles = set(tile_iterator(parent, min_zoom, max_zoom))
    existing = get_existing_tiles(layer.id, min_zoom, max_zoom)
    n_tiles = len(tiles)
    successes = 0
    failures = 0
    intersection = tiles & existing
    already_downloaded = len(intersection)

    tiles = list(tiles - existing)
    to_download = len(tiles)

    print(f"{already_downloaded} of {n_tiles} tiles already downloaded")

    for i, tile in enumerate(tiles):
        #print(f"{layer.name} tile {tile.z}/{tile.x}/{tile.y}")
        res = await download_tile(client, tile, layer)
        if res is None:
            already_downloaded += 1
        elif res:
            successes += 1
        else:
            failures += 1
        if i % 10 == 0:
            print(f"{i} of {to_download} tiles processed")
            print(f"successes: {successes}, failures: {failures}, already downloaded: {already_downloaded}")

def get_existing_tiles(layer_id, min_zoom, max_zoom):
    res = db.run_query("""SELECT z, x, y FROM tile_cache.tile WHERE layer = :layer_id AND z >= :min_zoom AND z <= :max_zoom""",
                       dict(layer_id=layer_id, min_zoom=min_zoom, max_zoom=max_zoom)).fetchall()
    return set(Tile(row.x, row.y, row.z) for row in res)

async def download_tile(client: AsyncClient, tile: Tile, layer):
    # Check if the tile is already in the database
    res = db.run_query("""
    SELECT 1
    FROM tile_cache.tile
    WHERE layer = :layer_id AND z = :z AND x = :x AND y = :y
    """, dict(layer_id=layer.id, z=tile.z, x=tile.x, y=tile.y)).fetchone()
    if res is not None:
        return None

    try:
        url = layer.url_pattern.format(z=tile.z, x=tile.x, y=tile.y)
        res = await client.get(url, params={"access_token": mapbox_token}, timeout=30)
        print(url)
        # Get the data as bytes
        data = res.content

        db.run_sql("""
            INSERT INTO tile_cache.tile (layer, z, x, y, data, compressed)
            VALUES (:layer_id, :z, :x, :y, :data, :is_zipped)
            """,
            dict(layer_id=layer.id, z=tile.z, x=tile.x, y=tile.y, data=data, is_zipped=_is_zipped(data[:2]))
        )
        db.session.commit()

        # Wait a random amount of time to avoid rate limiting
        await sleep(uniform(0.2, 1))
        return True
    except HTTPException as e:
        print(f"Failed to download tile: {e}")
        return False


def _is_zipped(data):
    return data[:2] == b"\x1f\x8b"


def get_parent_tile(region_id: int):
    res = db.run_query("""
    SELECT (tile_utils.parent_tile(geometry)).*
    FROM tile_cache.region
    WHERE id = :id
    """, dict(id=region_id)).fetchone()
    if res is None:
        return Tile(0, 0, 0)
    else:
        return Tile(res.x, res.y, res.z)


def _print_info(row):
    print(f"[dim]#{row.id}:[/dim] {row.name}")

def _print_val(name, value):
    print(f"[dim]{name}:[/dim] {value}")

def tile_iterator(tile: Tile, min_zoom: int, max_zoom: int):
    # Start with underscaled tiles, if there are any
    for z in range(min_zoom, max_zoom+1):
        if z < tile.z:
            yield tms.parent(tile, zoom=z)
        if z == tile.z:
            yield tile
        else:
            yield from tms.children(tile, zoom=z)


