serve:
	poetry run uvicorn macrostrat.map_cache.main:app --log-level debug --reload --port 8004

create:
	poetry run cache create

container:
	docker build -t macrostrat/map-cache .
