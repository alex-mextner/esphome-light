#!/usr/bin/env bash
# Point git at the repo's committed hooks (.githooks/), which delegate the
# gate events to the machine's global hook composers and add a post-commit
# HA sync. Run once after cloning. core.hooksPath is local config, not
# version-controlled, so it doesn't travel with the repo.
set -euo pipefail
cd "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
git config --local core.hooksPath .githooks
echo "install-hooks: core.hooksPath -> .githooks"
