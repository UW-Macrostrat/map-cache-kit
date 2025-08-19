FROM python:3.11

RUN pip install poetry==1.8.4


WORKDIR /app/

# Copy only requirements to cache them in docker layer
# Right now, Poetry lock file must exist to avoid hanging on dependency resolution
COPY ./deps/tile-utils/ /app/deps/tile-utils/
COPY ./pyproject.toml ./poetry.lock /app/

RUN poetry install --no-interaction --no-ansi --no-root --no-dev

EXPOSE 8000

# Creating folders, and files for a project:
COPY ./ /app/

# Install the root package
RUN poetry install --no-interaction --no-ansi --no-dev

CMD uvicorn --host 0.0.0.0 --port 8000 macrostrat.map_cache.main:app
