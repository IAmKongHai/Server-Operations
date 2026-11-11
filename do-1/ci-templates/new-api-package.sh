#!/usr/bin/env bash
# Zero-invasion external build & package script for upstream QuantumNous/new-api.
# Keeps /Users/konghai/code/Project/new-api 100% clean for `git pull`.
#
# Usage:
#   ./do-1/ci-templates/new-api-package.sh [/path/to/new-api] [--deploy]
set -euo pipefail

repo_dir="/Users/konghai/code/Project/new-api"
do_deploy=false
for arg in "$@"; do
  if [[ $arg == "--deploy" ]]; then
    do_deploy=true
  else
    repo_dir=$arg
  fi
done

cd "$repo_dir"
sha=${GITHUB_SHA:-$(git rev-parse HEAD)}
[[ $sha =~ ^[0-9a-f]{40}$ ]]
version=$(git describe --tags --always 2>/dev/null || echo "${sha:0:8}")

out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT

# 1. Build frontend into web/dist (gitignored in upstream repo)
if [[ ${SKIP_WEB:-0} != "1" ]]; then
  (
    cd web
    bun install --frozen-lockfile
    DISABLE_ESLINT_PLUGIN='true' VITE_REACT_APP_VERSION="$version" bun run build
  )
fi

# 2. Cross-compile static Linux amd64 Go binary with embedded web/dist
go mod download
pgo_file="$(go list -m -f '{{.Dir}}' github.com/Calcium-Ion/moejs)/default.pgo"
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 GOEXPERIMENT=greenteagc \
  go build -trimpath \
  -pgo="$pgo_file" \
  -ldflags "-s -w -X 'github.com/QuantumNous/new-api/common.Version=${version}'" \
  -o "$out/new-api" .

printf '%s\n' "$sha" > "$out/version.txt"
archive="${RUNNER_TEMP:-/tmp}/new-api-$sha.tar.gz"
tar -czf "$archive" -C "$out" .
printf 'Packaged %s\n' "$archive"

if [[ $do_deploy == true ]]; then
  printf 'Deploying %s to do-1...\n' "$sha"
  ssh do-1 "/usr/local/sbin/new-api-deploy $sha" < "$archive"
fi
