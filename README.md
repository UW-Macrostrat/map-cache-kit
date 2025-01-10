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

