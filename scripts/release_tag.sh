#!/usr/bin/env bash
# scripts/release_tag.sh — create the §11.4.151 prefixed release tag.
#   usage: bash scripts/release_tag.sh <version>     # e.g. 1.0.0-dev-0.0.1
# Produces an annotated tag "<PREFIX>-<version>" where <PREFIX> comes ONLY from
# scripts/release_prefix.sh (no prefix literal lives here). The SAME invocation
# is run in the main repo and in EVERY owned submodule so one release shares one
# prefix (§11.4.151) and fans out to every upstream (§2.1, never force-push §11.4.113).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
version="${1:?usage: release_tag.sh <version>   e.g. 1.0.0-dev-0.0.1}"
prefix="$("$here/release_prefix.sh")"          # decoupled resolution
tag="${prefix}-${version}"

# Preconditions enforced by caller/CI BEFORE this runs: §11.4.40 full-suite GREEN
# + §11.4.113 merged onto latest main. This script only does naming + tag create.
git tag -a "$tag" -m "Release $tag"
printf 'created tag: %s\n' "$tag"
printf 'fan-out (§2.1): git push origin "%s"   # origin pushes to every upstream\n' "$tag"
