from fastapi import FastAPI, Response, Request
from fastapi.middleware.cors import CORSMiddleware

from .config import db
from macrostrat.utils import get_logger, setup_stderr_logs
from re import compile

log = get_logger(__name__)

setup_stderr_logs(__name__)

app = FastAPI()

app.add_middleware(CORSMiddleware,
                   allow_origins=["*"],
                   allow_credentials=True,
                   allow_methods=["*"],
                   allow_headers=["*"])

@app.get("/")
def root_route():
    """The root of the tile cache API"""

    return {"message": "Hello World"}


@app.get("/file")
def file(request: Request):
    q = request.query_params
    url = q.get("url")
    log.debug(url)

    # Split query string and remove it
    if "?" in url:
        url = url.split("?")[0]

    res = db.run_query("SELECT data, content_type FROM tile_cache.file WHERE url = :url", dict(url=url)).fetchone()

    if res is None:
        return Response("Not found in cache", status_code=404)

    return Response(res.data, media_type=res.content_type)

exp = compile(r"/\d+/\d+/\d+")

@app.get("/tiles/{route:path}")
def tile(request: Request, route: str):
    q = request.query_params
    domain = q.get("x-cache-domain")

    url = domain + "/" + route

    url1 = transform_request_to_cache_key(url)

    log.info(url)
    log.info(url1)

    matches = exp.findall(url)
    assert len(matches) == 1

    match = matches[0]

    z,x,y = [int(r) for r in match[1:].split("/")]

    # Find the appropriate layer in the database if it exists
    res = db.run_query("SELECT id, content_type FROM tile_cache.layer WHERE url_pattern = :pattern", dict(pattern=url1)).fetchone()
    layer_id = res.id
    content_type = res.content_type

    tile_data = db.run_query("SELECT data FROM tile_cache.tile WHERE layer = :layer AND x = :x AND y = :y AND z = :z", dict(
        layer = layer_id,
        x = x,
        y = y,
        z = z
    )).fetchone()
    data = tile_data.data

    n = len(data)
    log.info(f"Length: {n}")

    return Response(data, media_type=content_type)


def transform_request_to_cache_key(url):
    """Get a cache key to try"""
    url1 = exp.sub("/{z}/{x}/{y}", url)

    if url1.endswith(".webp"):
        url1 = url1[:-5]+ ".png"

    return url1

