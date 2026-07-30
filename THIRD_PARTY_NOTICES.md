# Third-Party Data and Assets

The MIT license covers the original package code, documentation, and synthetic
inputs created for this repository. It does not relicense third-party datasets
or materials derived from them. Source-specific terms continue to apply.

Raw external inputs are not committed. Each external adapter records its
source URL, version or commit, hash, and known terms in `sources.toml` or an
equivalent manifest.

## Map backgrounds

The tracked contiguous-U.S. map background combines Natural Earth II shaded
relief with a simplified 2018 U.S. Census cartographic boundary layer. Both
sources are public domain. Source URLs, archive hashes, and transformations
are recorded in `plots/assets/README.md`.

## Cow surface

The optional three-dimensional cow example downloads John Burkardt's PLY
sample under the GNU Lesser General Public License, version 3. The mesh is not
committed. Its source, license, and hash are recorded in
`examples/cow/THIRD_PARTY.md` and `examples/cow/sources.toml`.

## Sioux Falls

The on-demand Sioux Falls adapter uses files from
`bstabler/TransportationNetworks` at the pinned commit recorded in
`examples/sioux_falls/sources.toml`. The upstream repository describes those
files as available for academic research. Source and generated model data are
not distributed by this package.

The practitioner guide contains derived Sioux Falls figures and tables. The
authors elected to distribute these scholarly illustrations with the source
citation while leaving the source and generated model data outside the
repository. This distribution does not relicense the upstream files.

## Seattle

The Seattle adapters refer to the Allen--Arkolakis replication archive, U.S.
Census data, a pinned 2017 King County GTFS feed, Census TIGER/Line geography,
and the 2017 King County Metro System Evaluation. Exact sources, hashes,
attribution, and known terms are recorded under `examples/seattle_urban/` and
`examples/seattle_multimodal/`.

The repository does not distribute the replication archive, GTFS feed, Census
responses, geographic archives, or Metro report. The authors elected to
distribute the derived guide figures and tables with the recorded source
attribution. Those illustrations remain subject to the applicable source
terms.

## Westeros

The Westeros adapter queries a public ArcGIS item owned by CreativeCarto. No
reuse license was listed in the item metadata when the source manifest was
created. Downloaded features and generated model inputs are therefore not
committed.

The practitioner guide contains derived Westeros figures and tables. The
authors elected to distribute these scholarly illustrations with attribution
to the ArcGIS item owner. No license is asserted for the source map or
downloaded features, and neither is distributed by this repository.

## Software dependencies

Julia and Python dependencies are resolved from their standard package
registries and are not vendored here. Their own licenses apply. Dependency
versions for the paper replication and plotting environment are recorded in
the locked manifests and requirements files.
