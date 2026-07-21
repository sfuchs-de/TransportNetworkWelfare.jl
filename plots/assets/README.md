# RSUE map assets

The publication maps use two pinned public-domain geographic layers so they
render deterministically without a live tile service.

- `conus_relief_50m.jpg` is a crop of Natural Earth II shaded relief with
  water, downloaded from
  `https://naturalearth.s3.amazonaws.com/50m_raster/NE2_50M_SR_W.zip`.
  The source ZIP has SHA-256
  `7e0e07089b699a3cccad98dd1b2446390d8e3f8c5006359d477a329cebcafaa9`.
- `conus_states_2018.geojson` is simplified from the U.S. Census Bureau's
  2018 1:20m state cartographic boundary file, downloaded from
  `https://www2.census.gov/geo/tiger/GENZ2018/shp/cb_2018_us_state_20m.zip`.
  The source ZIP has SHA-256
  `95902e4cda23f5f403e576d1bcd0e54a0f453d9b81893b080f4c15029302e348`.

The raster was cropped to `[-125, -66] x [24, 50]` and resized to
`2400 x 1058` pixels. The state layer was transformed to EPSG:4326, reduced
to the contiguous states, and simplified at 0.015 degrees. Natural Earth and
U.S. Census Bureau cartographic boundary files are public domain.
