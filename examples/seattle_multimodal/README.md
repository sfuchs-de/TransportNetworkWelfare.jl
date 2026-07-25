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

## Exact 2017 source acquisition

Raw sources are not committed. Choose an external cache. A Census API key is
needed only when the pinned ACS response is not already present:

```bash
export SEATTLE_TRANSIT_DATA_ROOT=/absolute/path/to/seattle-transit-2017
export CENSUS_API_KEY=...
julia --project=. examples/seattle_multimodal/download_sources.jl \
  --data-root "$SEATTLE_TRANSIT_DATA_ROOT"
```

The downloader obtains and verifies the Allen--Arkolakis source files, ACS
B08301 response, Metro evaluation report, and 2017 Census map layers. It also
requires the exact historical GTFS recorded in `sources.toml`. The default
download is the public Mobility Database copy of the TransitFeeds archive,
dataset `mdb-267-20170614`. Its SHA-1
`ad172e653aa881557a5f3cb84f2ace6819308600`, with service from 8 June through
22 September 2017, matches the feed version independently catalogued by
Transitland. The acquisition gate also verifies the archive SHA-256, 223
routes, 7,718 stops, 33,837 trips, 442,686 shape points, 1,193,603 stop times,
and every file hash. It never substitutes the current King County feed.

To use a previously downloaded copy instead, set:

```bash
export SEATTLE_GTFS_2017_ARCHIVE=/absolute/path/to/ad172e653aa881557a5f3cb84f2ace6819308600.zip
```

The downloader verifies it before extraction. `TRANSITLAND_API_KEY` remains a
fallback for archive-enabled accounts if the public source is removed from a
custom manifest. `AA_REPLICATION_ARCHIVE` provides the corresponding optional
offline input for the Allen--Arkolakis ZIP. Verified cached ACS responses also
work offline. API keys are omitted from errors and manifests.

Transit scheduling and geographic data provided by permission of King County.

## Build and analyze

Use the economic-geography application's $\eta=1.099$ as the declared
baseline:

```bash
julia --project=. examples/seattle_multimodal/prepare.jl \
  --data-root "$SEATTLE_TRANSIT_DATA_ROOT" --eta 1.099 --offline
julia --project=. examples/seattle_multimodal/build_impacts.jl \
  --data-root "$SEATTLE_TRANSIT_DATA_ROOT"
```

The builder writes separate road, bus, rail/streetcar, and ferry
configurations. Each contains every observed mode; only the policy mode
changes. Because some transit arcs are not reciprocal, transit configurations
request directed results. The artifact builder reports reciprocal corridor
sums separately without relabeling one-way arcs as physical links.

Observed edge-mode shares are the implied modal shifters that reproduce the
constructed ACS-based modal baseline in the hat/IFT system.
The transferred $\eta=1.099$ controls substitution around that baseline; it
is not estimated from Seattle data. The artifacts include sensitivity at
$0.75$, $0.90$, $1.099$, $1.25$, and $1.40$.

An optional terminal-congestion diagnostic can be generated with
`--terminal-lambda VALUE`. The value must be supplied explicitly and is not
part of the baseline Seattle candidate.

## Policies and outputs

The link experiment reduces one directed edge-mode primitive generalized cost
by one percent. Reciprocal corridor results sum the two directional
elasticities only when both directions exist.

`route_bundles.csv` maps each named GTFS route to the unique grid edge-mode
pairs that it traverses. A route-corridor experiment reduces the aggregate
mode cost on each mapped segment by one percent. On a segment shared by
several services, this is a corridor intervention rather than a claim that
only one operator's vehicles improve.

A named route is reported only when its complete mapped corridor lies on the
model's positive-flow support. The build manifest reports the number and share
of routes excluded by this gate; it never shortens a route to its active
segments.

The impact builder writes directed and corridor results for road, each transit
mode, and all transit. It also writes top-30 link and route tables,
traditional-versus-extended correlations, nonlinear finite-difference checks,
the $\eta$ sensitivity path, and a non-calibrating comparison of GTFS service
activity with the Metro report's route ridership.

The figure set includes three displays modeled on the Seattle figures in Allen
and Arkolakis:

- the observed 2017 road and GTFS networks beside the constructed multimodal
  network;
- road, bus, rail/streetcar, and ferry welfare effects on a common scale; and
- traditional and extended transit effects on a common scale.

Node area reflects the sum of residence and workplace commuter mass. Line
widths in the constructed-network panel reflect baseline model flow. Map
colors in the welfare panels are gains from a one-percent improvement, not
traffic shares. Figures are written as PDF and transparent PNG files. The
generated `analysis.md` distinguishes directed experiments from corridor sums
and records the quantitative comparisons used to interpret the maps.

## Declared approximations

- Transit assignment uses average scheduled in-vehicle time plus one-half of
  the edge-specific scheduled headway.
- Stops are mapped to grid nodes within a declared distance threshold.
- Transit trips without a path in the mapped network are reassigned to road
  and reported by origin. The build fails if this exceeds five percent of
  requested transit commuters.
- A negligible, declared reciprocal circulation keeps all 1,384 published
  road arcs interior without changing node flow balances.
- Grid nodes serve as transfer points; walking access and transfer nodes are
  not modeled separately.
- Bus passengers do not yet enter the road-mode congestion stock. That
  cross-mode congestion channel requires an extension to the shared transport
  operator.

These choices make the candidate reproducible and auditable. They do not make
it an externally validated Seattle calibration.
