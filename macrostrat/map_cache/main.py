from fastapi import FastAPI

app = FastAPI()

@app.get("/")
def root_route():
    """The root of the tile cache API"""

    return {"message": "Hello World"}
