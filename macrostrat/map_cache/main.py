import base64


from fastapi import FastAPI, Response, Request
from fastapi.middleware.cors import CORSMiddleware

from .config import db
from macrostrat.utils import get_logger

log = get_logger(__name__)

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
