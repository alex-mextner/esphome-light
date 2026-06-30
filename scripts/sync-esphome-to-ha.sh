#!/usr/bin/env bash
# Push this repo's ESPHome config to the HA host's /home/ultra/esphome/ so the
# ESPHome Dashboard (Docker container on host `home`) mirrors this repo. Source
# of truth is THIS repo; the host dir is a deployed mirror.
#
# Runs from .githooks/post-commit (repo-local core.hooksPath override) and can
# be run manually:  bash scripts/sync-esphome-to-ha.sh
#
# Design:
# - ADD/UPDATE ONLY: a file removed/renamed in the repo is NOT deleted on the
#   host (no --delete). Remove stale host files by hand.
# - Sources the COMMITTED (HEAD) version, not the working tree, so a commit made
#   with unstaged WIP still mirrors exactly what was committed.
# - ATOMIC remote write: stream into a temp file, mv into place only on success,
#   so a dropped SSH (Tailscale on this node is flaky) never leaves a truncated
#   YAML for the Dashboard to load.
# - NON-FATAL: any SSH failure warns and exits 0.
# - secrets.yaml is intentionally NOT pushed (shared with the esphome-ir device;
#   overwriting it here would drop that device's secrets).
#
# Override via .env: HA_DEPLOY_USER (default ultra), HA_DEPLOY_HOST (default
# home.tailbfe8ea.ts.net). Do NOT reuse HA_SSH_USER/HA_HOST from .env — those
# point at the DEAD HAOS add-on route (hassio@192.168.0.25).

set -uo pipefail

REPO="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
cd "$REPO"

[[ -f .env ]] && { set -a; source .env; set +a; }

HA_DEPLOY_USER="${HA_DEPLOY_USER:-ultra}"
HA_DEPLOY_HOST="${HA_DEPLOY_HOST:-home.tailbfe8ea.ts.net}"
DEST="/home/ultra/esphome"
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 -o BatchMode=yes)

# timeout(1) is GNU coreutils; fall back to gtimeout, else run ssh bare
# (BatchMode + ConnectTimeout already bound the hang).
TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || true)"

ssh_write() {  # $1 = remote shell command; stdin is piped in
  if [[ -n "$TIMEOUT_BIN" ]]; then
    "$TIMEOUT_BIN" 30 ssh "${SSH_OPTS[@]}" "$HA_DEPLOY_USER@$HA_DEPLOY_HOST" "$1"
  else
    ssh "${SSH_OPTS[@]}" "$HA_DEPLOY_USER@$HA_DEPLOY_HOST" "$1"
  fi
}

push_file() {
  local path="$1" dst="$2"
  if ! git cat-file -e "HEAD:$path" 2>/dev/null; then
    echo "sync-esphome-to-ha: $path not in HEAD — skipped (add/update-only; remote not deleted)" >&2
    return 0
  fi
  if git show "HEAD:$path" | ssh_write "cat > '$dst.tmp' && mv '$dst.tmp' '$dst'"; then
    echo "sync-esphome-to-ha: pushed $path -> $dst"
    return 0
  fi
  echo "sync-esphome-to-ha: WARNING could not push $path (host unreachable / Tailscale SSH re-auth needed) — remote left unchanged" >&2
  return 1
}

failed=0
push_file esp32-c3-light.yaml "$DEST/esp32-c3-light.yaml" || failed=1
push_file deploy/ha-host-AGENTS.md "$DEST/AGENTS.md" || failed=1

if [[ $failed -ne 0 ]]; then
  echo "sync-esphome-to-ha: one or more pushes failed (commit NOT affected — post-commit is non-blocking)." >&2
  echo "sync-esphome-to-ha: re-run after restoring host access: bash scripts/sync-esphome-to-ha.sh" >&2
fi
exit 0
