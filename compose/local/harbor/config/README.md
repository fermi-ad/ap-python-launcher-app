# Local Harbor config scaffold

This directory contains the vendored local Harbor configuration scaffold for the future Compose-based Harbor profile.

The initial asset set includes:
- [`harbor.yml`](../harbor.yml) with local HTTP settings bound to `http://localhost:8081`
- [`env/common.sh`](../env/common.sh) with common local Harbor defaults

Next implementation step:
- add the Harbor support service definitions and wire them into [`compose.local.yaml`](../../../compose.local.yaml) under the `harbor` and `full` profiles
- mount or generate the remaining config required by the vendored local Harbor deployment
