# Transport Network Welfare project

This directory is a complete project for `TransportNetworkWelfare.jl`. It can
be moved outside the package repository. To use your own network:

1. Replace `data/nodes.csv` and `data/edge_modes.csv` while preserving their
   headers.
2. Edit the model, congestion, policy, and sensitivity settings in
   `config.toml`.
3. Validate before computing results:

   ```bash
   julia --project=/path/to/TransportNetworkWelfare.jl \
     /path/to/TransportNetworkWelfare.jl/bin/tnw.jl validate config.toml
   ```

4. Run `decompose` after validation. Outputs are written to `output/`.

The edge-mode flows must be in the units declared by `flow_conversion` and
must satisfy node-level incoming/outgoing traffic accounting. The package does
not silently balance, symmetrize, pad, or rescale generic data. See the package
documentation under `docs/src/own-data.md` for the full data contract.
