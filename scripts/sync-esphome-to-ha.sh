#!/usr/bin/env bash
# Push this repo's ESPHome config to the HA host's /home/ultra/esphome/ so the
# ESPHome Dashboard (Docker container on host `home`) sees the same files as
# this repo. Source of truth is THIS repo; the host dir is a deployed mirror.
#
# Runs as a post-commit hook (.git/hooks/post-commit) and can be run manually:
#   bash scripts/sync-esphome-to-ha.sh
#
# Non-fatal by design: a blocked/failed SSH (e.g. Tailscale re-auth needed)
# logs a warning and exits 0 so it never breaks a commit.
#
# SSH is key-based as `ultra` over Tailscale. Override host/user via .env:
#   HA_DEPLOY_USER (default: ultra)
#   HA_DEPLOY_HOST (default: home.tailbfe8ea.ts.net)
# NOTE: do NOT reuse HA_SSH_USER/HA_HOST from .env here — those point at the
# DEAD HAOS add-on route (hassio@192.168.0.25), not the live Docker host.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

[[ -f .env ]] && { set -a; source .env; set +a; }

HA_DEPLOY_USER="${HA_DEPLOY_USER:-ultra}"
HA_DEPLOY_HOST="${HA_DEPLOY_HOST:-home.tailbfe8ea.ts.net}"
DEST="/home/ultra/esphome"
SSH_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes)

push_file() {
  local src="$1" dst="$2"
  [[ -f "$src" ]] || return 0
  if timeout 30 ssh "${SSH_OPTS[@]}" "$HA_DEPLOY_USER@$HA_DEPLOY_HOST" "cat > '$dst'" < "$src"; then
    echo "sync-esphome-to-ha: pushed $src -> $dst"
    return 0
  fi
  echo "sync-esphome-to-ha: WARNING could not push $src (host unreachable / Tailscale SSH re-auth needed) — skipped" >&2
  return 1
}

# NOTE: secrets.yaml is intentionally NOT pushed — the host secrets.yaml is
# SHARED with the esphome-ir device; overwriting it from here would drop the
# IR device's secrets. Append new !secret values to the host file by hand.
failed=0
push_file esp32-c3-light.yaml "$DEST/esp32-c3-light.yaml" || failed=1
push_file deploy/ha-host-AGENTS.md "$DEST/AGENTS.md" || failed=1

if [[ $failed -ne 0 ]]; then
  echo "sync-esphome-to-ha: one or more pushes failed (commit NOT blocked)." >&2
  echo "sync-esphome-to-ha: re-run after restoring host access: bash scripts/sync-esphome-to-ha.sh" >&2
fi
exit 0
