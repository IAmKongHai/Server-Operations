#!/usr/bin/env bash
# Zero-invasion external build & package script for upstream Wei-Shaw/sub2api.
# Keeps /Users/konghai/code/Project/sub2api 100% clean for `git pull`.
#
# Usage:
#   ./do-1/ci-templates/sub2api-package.sh [/path/to/sub2api] [--deploy]
set -euo pipefail

repo_dir="/Users/konghai/code/Project/sub2api"
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
build_date=$(date -u +%Y-%m-%dT%H:%M:%SZ)

out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT

# 1. Build frontend (outputs to backend/internal/web/dist, gitignored in upstream repo)
# Pin pnpm@9 to match sub2api's lockfile v9 without modifying pnpm-lock.yaml
(
  cd frontend
  npx -y pnpm@9 install --frozen-lockfile --prefer-offline
  npx -y pnpm@9 run build
)

# 2. Cross-compile static Linux amd64 Go binary with -tags embed
(
  cd backend
  version_val=$(./scripts/resolve-version.sh 2>/dev/null || echo "${sha:0:8}")
  CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -tags embed -trimpath \
    -ldflags="-s -w -X main.Version=${version_val} -X main.Commit=${sha} -X main.Date=${build_date} -X main.BuildType=release" \
    -o "$out/sub2api" ./cmd/server
)

cp -a backend/resources "$out/resources"
printf '%s\n' "$sha" > "$out/version.txt"
archive="${RUNNER_TEMP:-/tmp}/sub2api-$sha.tar.gz"
tar -czf "$archive" -C "$out" .
printf 'Packaged %s\n' "$archive"

if [[ $do_deploy == true ]]; then
  printf 'Deploying %s to do-1...\n' "$sha"
  ssh do-1 "/usr/local/sbin/sub2api-deploy $sha" < "$archive"
fi
