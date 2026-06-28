# AGENTS.md — Home Assistant ESPHome config host (DEPLOYED MIRROR)

This directory (`/home/ultra/esphome/`) is the ESPHome Dashboard's `/config`
(Docker container `homeassistant-esphome-1`, port 6052, on host `home`). It is a
**deployed mirror — NOT the source of truth.**

## Source of truth lives on the dev Mac (Alex's machine), in git repos

| File(s) in this directory | Source repo on the dev Mac |
|---|---|
| `esp32-c3-light.yaml` | `~/xp/esphome-light` |
| `esp32.yaml`, `universal_remote.yaml`, `samsung_tv.yaml`, `haier_ac.yaml`, `projector.yaml`, `ir_remote.h`, `components/` | `~/xp/esphome-ir` |
| `secrets.yaml` | shared wifi creds; hand-edited on both sides |

## Rules for any agent or human working here

- **Do NOT hand-edit files in this directory.** Each source repo's `post-commit`
  hook (`scripts/sync-esphome-to-ha.sh`) overwrites them on every commit. Edits
  made directly here are silently lost on the next sync.
- To change a device: edit the file in its **source repo on the dev Mac**, commit
  (the commit auto-syncs the file here), then flash from the Dashboard or with
  `esphome run`.
- This `AGENTS.md` is itself generated from
  `~/xp/esphome-light/deploy/ha-host-AGENTS.md`. Edit it there, not here.
