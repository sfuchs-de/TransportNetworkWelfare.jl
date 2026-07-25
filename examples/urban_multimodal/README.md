# Multimodal urban commuting example

This four-location example uses the same recursive route and modal operators as
the economic-geography model. Road and transit are active on every directed
edge. The network contains alternative routes, road-edge congestion, and
endpoint transit-terminal congestion.

Residence shares, workplace shares, OD flows, and edge-mode flows are generated
from one contractive route kernel. No balancing occurs inside the package.

```bash
julia --project=. bin/tnw.jl validate examples/urban_multimodal/config.toml
julia --project=. bin/tnw.jl analyze examples/urban_multimodal/config.toml
julia --project=. bin/tnw.jl decompose examples/urban_multimodal/config.toml
```

The example is synthetic and distributable. It is the package's multimodal
urban verification fixture; it is not calibrated to Seattle.
