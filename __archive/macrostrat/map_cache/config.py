from macrostrat.database import Database
from dotenv import load_dotenv
from os import environ
import morecantile

load_dotenv()

db = Database(environ["MAP_CACHE_DATABASE_URL"])

mapbox_token = environ["MAPBOX_API_TOKEN"]

tms = morecantile.tms.get("WebMercatorQuad")

