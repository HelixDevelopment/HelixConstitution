#!/usr/bin/env bash
# install_upstreams.sh — Configure every declared upstream as a local
# git remote so a single push fans out to every provider.
#
# Reads ./upstreams/*.sh (preferred, §11.4.29 / CONST-052 lowercase
# snake_case) OR ./Upstreams/*.sh (legacy, kept working during the
# migration window). When both directories exist, the lowercase
# variant wins; old projects with only `Upstreams/` continue to
# function unchanged.
#
# Each declaration MUST export UPSTREAMABLE_REPOSITORY=<git-url>.
#
# Usage (from the constitution submodule root):
#   bash install_upstreams.sh
#
# Constitution: §2.1 "Multi-upstream push is the norm";
# §11.4.29 "Lowercase-Snake_Case-Naming Mandate".

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve the upstreams declaration directory. §11.4.29 transition:
# prefer the lowercase form; fall back to the legacy uppercase form so
# old checkouts keep working until they migrate. If neither exists,
# fail with a directed error pointing the user at the snake_case
# canonical name.
if [[ -d "${SCRIPT_DIR}/upstreams" ]]; then
    UPSTREAMS_DIR="${SCRIPT_DIR}/upstreams"
elif [[ -d "${SCRIPT_DIR}/Upstreams" ]]; then
    UPSTREAMS_DIR="${SCRIPT_DIR}/Upstreams"
    echo "WARN: using legacy 'Upstreams/' — please rename to 'upstreams/' per §11.4.29" >&2
else
    echo "ERROR: upstreams directory not found (expected ${SCRIPT_DIR}/upstreams or ${SCRIPT_DIR}/Upstreams)" >&2
    exit 1
fi

# Must run inside a git work-tree
if ! git -C "${SCRIPT_DIR}" rev-parse --git-dir > /dev/null 2>&1; then
    echo "ERROR: ${SCRIPT_DIR} is not a git repository" >&2
    exit 1
fi

declare -a UPSTREAM_URLS=()
declare -a UPSTREAM_NAMES=()

# Decode an UPSTREAMABLE_REPOSITORY URL into a short remote name.
# - github.com → github
# - gitlab.com → gitlab
# - gitflic.ru → gitflic
# - gitverse.ru → gitverse
# - bitbucket.org → bitbucket
# - codeberg.org → codeberg
# - <anything>.com → first label
remote_name_for_url() {
    local url="${1:-}"
    case "${url}" in
        *github.com*) echo "github" ;;
        *gitlab.com*) echo "gitlab" ;;
        *gitflic.ru*) echo "gitflic" ;;
        *gitverse.ru*) echo "gitverse" ;;
        *bitbucket.org*) echo "bitbucket" ;;
        *codeberg.org*) echo "codeberg" ;;
        *)
            # Strip protocol + auth, take the host's first label
            local host
            host="$(echo "${url}" | sed -E 's#^[a-z]+://([^/]*)/.*#\1#; s#^git@([^:]*):.*#\1#')"
            echo "${host%%.*}"
            ;;
    esac
}

# Read every Upstreams/*.sh declaration
shopt -s nullglob
for decl in "${UPSTREAMS_DIR}"/*.sh; do
    # shellcheck disable=SC1090
    unset UPSTREAMABLE_REPOSITORY
    . "${decl}"
    if [[ -z "${UPSTREAMABLE_REPOSITORY:-}" ]]; then
        echo "WARN: ${decl} did not export UPSTREAMABLE_REPOSITORY — skipping" >&2
        continue
    fi
    UPSTREAM_URLS+=("${UPSTREAMABLE_REPOSITORY}")
    UPSTREAM_NAMES+=("$(remote_name_for_url "${UPSTREAMABLE_REPOSITORY}")")
done
shopt -u nullglob

if [[ ${#UPSTREAM_URLS[@]} -eq 0 ]]; then
    echo "ERROR: no upstreams declared in ${UPSTREAMS_DIR}" >&2
    exit 1
fi

echo "Detected ${#UPSTREAM_URLS[@]} upstreams:"
for i in "${!UPSTREAM_URLS[@]}"; do
    echo "  ${UPSTREAM_NAMES[$i]} → ${UPSTREAM_URLS[$i]}"
done
echo

# Configure each as a dedicated named remote (fetch + push to its own URL)
for i in "${!UPSTREAM_URLS[@]}"; do
    name="${UPSTREAM_NAMES[$i]}"
    url="${UPSTREAM_URLS[$i]}"
    if git -C "${SCRIPT_DIR}" remote get-url "${name}" >/dev/null 2>&1; then
        git -C "${SCRIPT_DIR}" remote set-url "${name}" "${url}"
        echo "Updated remote: ${name}"
    else
        git -C "${SCRIPT_DIR}" remote add "${name}" "${url}"
        echo "Added remote: ${name}"
    fi
done

# Configure `origin` to fan out to every upstream on push.
# Fetch URL stays at the first upstream (so `git pull` deterministically
# uses one provider as source of truth).
if ! git -C "${SCRIPT_DIR}" remote get-url origin >/dev/null 2>&1; then
    git -C "${SCRIPT_DIR}" remote add origin "${UPSTREAM_URLS[0]}"
    echo "Added remote: origin (fetch from ${UPSTREAM_NAMES[0]})"
else
    git -C "${SCRIPT_DIR}" remote set-url origin "${UPSTREAM_URLS[0]}"
fi

# Clear any existing push URLs on origin, then add one per upstream
# Robust technique: re-set the (fetch) URL to itself with --push-only behaviour
git -C "${SCRIPT_DIR}" remote set-url --delete --push origin '.*' 2>/dev/null || true
for url in "${UPSTREAM_URLS[@]}"; do
    git -C "${SCRIPT_DIR}" remote set-url --add --push origin "${url}"
done

echo
echo "✓ origin push URLs:"
git -C "${SCRIPT_DIR}" remote get-url --push --all origin | sed 's/^/    /'

echo
echo "Done. Verify with:  git remote -v"
