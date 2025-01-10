from typer import Typer
from macrostrat.database import Database
from dotenv import load_dotenv
from os import environ
from pathlib import Path
from rich import print
import morecantile
from morecantile import Tile

load_dotenv()

db = Database(environ["MAP_CACHE_DATABASE_URL"])

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
def get_region(name: str, *, max_zoom: int = None):
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
    n_tiles = sum(2**i for i in range(dz+1))
    _print_val("Tiles per layer", n_tiles)

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
