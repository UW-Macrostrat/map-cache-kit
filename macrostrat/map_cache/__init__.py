from typer import Typer
from macrostrat.database import Database
from dotenv import load_dotenv
from os import environ
from pathlib import Path


load_dotenv()

db = Database(environ["MAP_CACHE_DATABASE_URL"])

cli = Typer()

__here__ = Path(__file__).parent


@cli.command()
def create():
    db.run_fixtures(__here__ / "fixtures")
    db.run_fixtures(__here__ / "fixtures" / "03-tile-utils")
