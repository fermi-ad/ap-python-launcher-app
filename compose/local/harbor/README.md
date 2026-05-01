# Local Harbor profile scaffold

This directory scaffolds a future real Harbor deployment integrated into [`compose.local.yaml`](../../compose.local.yaml).

Planned scope for the follow-up implementation:
- vendor the minimal Harbor deployment assets needed for a local HTTP-based development setup
- add the required Harbor supporting services under a dedicated Compose profile
- wire [`app-dev`](../../compose.local.yaml) to use the local Harbor base URL for Harbor-focused testing

Expected future assets in this directory may include:
- Harbor config templates
- generated config files
- storage directories or bind-mount roots
- helper scripts for bootstrap or seeding

For now, this scaffold exists so the Harbor-focused profile structure is explicit in the repo layout.
