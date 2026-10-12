#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$repo_dir/H3_REFERENCE_DIRECTOR_01_V2_RUNPOD_DISTRIBUTION/INSTALL_H3_REFERENCE_DIRECTOR_V2_RUNPOD.sh" "$@"
