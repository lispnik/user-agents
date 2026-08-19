#!/usr/bin/env bash
#
# update-data.sh --- Sync data/user-agents.json.gz with upstream.
#
# Downloads the current upstream dataset, and if it differs from the vendored
# copy, replaces it and releases a new version of this port: version.sexp,
# src/version.lisp, data/upstream.sexp and CHANGELOG.md are all regenerated.
#
# Exits 0 whether or not anything changed; read CHANGED / VERSION from the file
# named by --result-file (or from $GITHUB_OUTPUT under GitHub Actions).
#
# Usage:
#   scripts/update-data.sh [--commit] [--tag] [--result-file PATH]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

UPSTREAM_REPO="${UPSTREAM_REPO:-intoli/user-agents}"
UPSTREAM_REF="${UPSTREAM_REF:-master}"
DATA_URL="${DATA_URL:-https://raw.githubusercontent.com/${UPSTREAM_REPO}/${UPSTREAM_REF}/src/user-agents.json.gz}"
PACKAGE_URL="${PACKAGE_URL:-https://raw.githubusercontent.com/${UPSTREAM_REPO}/${UPSTREAM_REF}/package.json}"

do_commit=false
do_tag=false
result_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --commit) do_commit=true; shift ;;
    --tag) do_tag=true; shift ;;
    --result-file) result_file="$2"; shift 2 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "update-data.sh: unknown option $1" >&2; exit 2 ;;
  esac
done

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "Fetching $DATA_URL"
curl --fail --silent --show-error --location -o "$work/user-agents.json.gz" "$DATA_URL"

# The npm version is recorded for provenance only; the sha256 of the data file
# is what actually decides whether we cut a new release.
upstream_version="unknown"
if curl --fail --silent --show-error --location -o "$work/package.json" "$PACKAGE_URL"; then
  upstream_version="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
                      "$work/package.json" | head -n 1)"
  upstream_version="${upstream_version:-unknown}"
fi
echo "Upstream package version: $upstream_version"

: "${result_file:=$work/result.env}"

UA_NEW_DATA="$work/user-agents.json.gz" \
UA_UPSTREAM_VERSION="$upstream_version" \
UA_SOURCE_URL="$DATA_URL" \
UA_RESULT_FILE="$result_file" \
  sbcl --noinform --non-interactive --load scripts/update.lisp

# shellcheck disable=SC1090
source "$result_file"

if [[ "$CHANGED" != "true" ]]; then
  echo "Already up to date at version $VERSION."
  exit 0
fi

echo "Released version $VERSION ($RECORDS records)."

if [[ "$do_commit" == true ]] && git rev-parse --git-dir >/dev/null 2>&1; then
  git add data/user-agents.json.gz data/upstream.sexp version.sexp \
          src/version.lisp CHANGELOG.md
  git commit -m "Update user agent dataset and release $VERSION

Upstream intoli/user-agents $upstream_version, $RECORDS records.
SHA-256 $NEW_SHA256."
  if [[ "$do_tag" == true ]]; then
    git tag -a "v$VERSION" -m "Version $VERSION"
  fi
fi
