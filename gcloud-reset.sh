#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025–present Srikanth Pagadarai

#!/usr/bin/env bash
set -euo pipefail

NUKE=0
if [[ "${1:-}" == "--nuke" ]]; then
  NUKE=1
fi

echo "==> Checking gcloud is installed..."
if ! command -v gcloud >/dev/null 2>&1; then
  echo "ERROR: gcloud not found on PATH." >&2
  exit 1
fi

# Never fail on cleanup steps so the script can finish gracefully
maybe() { "$@" >/dev/null 2>&1 || true; }

echo "==> Determine active configuration..."
ACTIVE_CFG="$(gcloud config configurations list --format='value(name)' --filter='is_active:true' || true)"

if [[ -z "${ACTIVE_CFG}" ]]; then
  echo "==> No active config; creating and activating 'wipe'..."
  maybe gcloud config configurations create wipe --quiet
  maybe gcloud config configurations activate wipe --quiet
  ACTIVE_CFG="wipe"
fi

# If we're on 'default' or any other, switch to 'wipe' to free them up for deletion
if [[ "${ACTIVE_CFG}" != "wipe" ]]; then
  echo "==> Switching active config to 'wipe'..."
  maybe gcloud config configurations create wipe --quiet
  maybe gcloud config configurations activate wipe --quiet
  ACTIVE_CFG="wipe"
fi

echo "==> Revoking credentials (logging out)..."
maybe gcloud auth revoke --all --quiet

echo "==> Unsetting common keys..."
maybe gcloud config unset account --quiet
maybe gcloud config unset project --quiet
maybe gcloud config unset core/account --quiet
maybe gcloud config unset core/project --quiet

echo "==> Deleting all configs except 'wipe'..."
for cfg in $(gcloud config configurations list --format='value(name)' || true); do
  if [[ "$cfg" == "wipe" ]]; then
    echo "    Skipping active config: wipe"
    continue
  fi
  echo "    Deleting: $cfg"
  maybe gcloud config configurations delete "$cfg" --quiet
done

if [[ $NUKE -eq 1 ]]; then
  echo "==> NUKE mode: removing ~/.config/gcloud (full reset)..."
  rm -rf "${HOME}/.config/gcloud"
  echo "==> Done. Fresh start."
  printf "\nNext:\n  gcloud init\n"
  exit 0
fi

echo "==> Leaving a single empty config named 'wipe' so gcloud stays happy."

