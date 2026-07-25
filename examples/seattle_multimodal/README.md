# Seattle multimodal urban candidate

This adapter applies the package's multimodal urban IFT to the Seattle grid
used by Allen and Arkolakis. It is a new candidate specification, not a
replication of their one-road-mode empirical exercise.

## What the original Seattle exercise used

The Allen-Arkolakis replication combines:

- a 217-location grid and 2017 LODES residence-to-workplace commuting flows;
- a 2016 HPMS road network;
- road travel times obtained from HERE; and
- HPMS annual average daily traffic as the road-traffic measure.

It does not contain a route-level public-transit network or public-transit
ridership. The Commute Seattle mode-split survey is cited descriptively in the
paper but is not an input to the published network calculation.

The historical road adapter in `examples/seattle_urban/` preserves those
inputs. It does not pass the package's recursive-flow accounting gate: AADT and
LODES measure different populations and imply a maximum normalized stock
disagreement of about `0.108`.

## Multimodal data contract

This candidate uses one internally coherent commuter population:

1. The complete 2017 LODES OD matrix supplies commuter masses and its row and
   column sums supply residence and workplace masses.
2. 2017 ACS five-year table B08301 supplies the share of commuters using public
   transit at each residential origin. Block-group estimates are allocated to
   the Allen-Arkolakis grid using their area crosswalk.
3. The pinned 14 June 2017 King County GTFS feed supplies weekday transit
   service, mode labels, and scheduled paths.
4. Allen-Arkolakis road travel times supply road paths.
5. OD commuters are routed by mode. The resulting road and transit edge flows
   therefore obey the urban accounting identity by construction.

GTFS is schedule data, not ridership data. ACS identifies origin mode shares,
not route choice. The 2017 King County Metro System Evaluation reports
route-level ridership and passenger-load measures and is retained as a
validation target; it is not used to manufacture an OD-to-route allocation.

## Required external sources

The raw sources are not committed. Set:

```bash
export AA_REPLICATION_ROOT=/path/to/extracted/ReplicationFinal
export SEATTLE_GTFS_2017_ROOT=/path/to/extracted/ad172e653aa881557a5f3cb84f2ace6819308600
export CENSUS_API_KEY=...
```

The GTFS directory must contain the exact historical feed recorded in
`sources.toml`. Transitland identifies it by SHA-1
`ad172e653aa881557a5f3cb84f2ace6819308600`, with service from 8 June through
22 September 2017. The builder verifies every GTFS file that it uses. It will
not silently substitute the current King County feed.

Historical Transitland downloads may require an account with feed-archive
access. A previously downloaded and extracted copy works offline.

Transit scheduling and geographic data provided by permission of King County.

## Build and analyze

Seattle does not provide an estimated modal elasticity for this model, so
`--eta` is mandatory:

```bash
julia --project=. examples/seattle_multimodal/prepare.jl --eta 1.099
julia --project=. bin/tnw.jl validate \
  examples/seattle_multimodal/generated/config.toml
julia --project=. bin/tnw.jl analyze \
  examples/seattle_multimodal/generated/config.toml
```

`1.099` is a possible sensitivity value inherited from the economic-geography
application. It is not a Seattle estimate. The generated manifest labels it as
user supplied.

For a cached ACS response:

```bash
julia --project=. examples/seattle_multimodal/prepare.jl \
  --eta 1.099 \
  --acs /path/to/acs_2017_king_county_b08301.json \
  --offline
```

An optional terminal-congestion diagnostic can be generated with
`--terminal-lambda VALUE`. The value must be supplied explicitly and is not
part of the baseline Seattle candidate.

## Declared approximations

- Transit assignment uses average scheduled in-vehicle time plus one-half of
  the edge-specific scheduled headway.
- Stops are mapped to grid nodes within a declared distance threshold.
- Transit trips without a path in the mapped network are reassigned to road
  and reported in the manifest.
- A negligible, declared reciprocal circulation keeps all 1,384 published
  road arcs interior without changing node flow balances.
- Grid nodes serve as transfer points; walking access and transfer nodes are
  not modeled separately.
- Bus passengers do not yet enter the road-mode congestion stock. That
  cross-mode congestion channel requires an extension to the shared transport
  operator.

These choices make the candidate reproducible and auditable. They do not make
it an externally validated Seattle calibration.
