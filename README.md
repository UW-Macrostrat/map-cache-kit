# Macrostrat map cache

A prototype caching system for maps.

This is meant to be generalized, pluggable, and usable on multiple platforms.
It is designed to serve data from static GIS files to tiled data formats,
possibly overlaying and compositing multiple layers.

It will consist of several components:

1. A map cache database that stores tiles and basic metadata
2. A tile server that can serve tiles to client applications
3. Downloader(s) that can fetch tiles from remote sources
4. Tilers that can represent locally- or cloud-stored GIS data (e.g., cloud-optimized GeoTIFFs) in tiled formats
5. A cache maintenance and expiry API
6. Web interfaces for cache management

The reference implementation will be in Python, but the key goal of the system is to be
usable on multiple platforms with similar semantics (e.g., in a mobile app).
The main goal will be to support a flexible map backend for multiple clients.

## Main goals

- Mapbox has great caching utilities, but in recent versions of their system they are moving towards
  a more proprietary model that is geared towards their own caching services (which are not documented
  for external use.)
- Mapbox caching services are tied to platform-specific native SDKs and cannot be directly used with
  other frontends, most notably web-based systems like Mapbox GL JS, Maplibre GL JS, etc.
- It is desirable to support on-device merging of data from multiple sources (e.g., local in-progress and global maps)

## To do

- Develop a wire format similar to Mapbox's "tile packs" system
- Support reading "composited" Mapbox tiles https://api.mapbox.com/v4/mapbox.mapbox-streets-v8,mapbox.mapbox-terrain-v2,mapbox.mapbox-bathymetry-v2/{z}/{x}/{y}.vector.pbf
