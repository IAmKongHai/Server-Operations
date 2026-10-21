#!/usr/bin/env bash
# set-uat-cut-token.sh — 把 UAT_CUT_TOKEN 写到 iCare 相关仓库的 Actions secret
#
# 用法：
#   ./scripts/set-uat-cut-token.sh
# 然后粘贴 Regenerate 得到的 PAT，回车（无回显）。
#
# 明文不写盘、不进 git、不打印。GitHub 也不会再显示旧值。
set -euo pipefail

SECRET_NAME=UAT_CUT_TOKEN

REPOS=(
  cypressoai/iCare-frontend-mas
  cypressoai/iCare-backend
  cypressoai/iCare-mobile-app
  cypressoai/iCare-public-backend
  cypressoai/iCare-terraform
  cypressoai/iCare-public-frontend
  cypressoai/iCare-Operations-backend
  cypressoai/iCare-Operations-frontend
)

command -v gh >/dev/null || { echo "gh CLI not found" >&2; exit 1; }
gh auth status >/dev/null || { echo "gh not logged in" >&2; exit 1; }

echo "Logged in as: $(gh api user --jq .login)"
echo "Will set ${SECRET_NAME} on ${#REPOS[@]} repos."
echo
echo -n "Paste the new PAT, then Enter (input hidden): "
IFS= read -r -s PAT
echo
if [[ -z "${PAT}" ]]; then
  echo "empty token" >&2
  exit 1
fi
# strip a trailing CR if pasted from some clipboard
PAT="${PAT%$'\r'}"
case "${PAT}" in
  github_pat_*|ghp_*) ;;
  *)
    echo "token does not look like a GitHub PAT (github_pat_ / ghp_)" >&2
    unset PAT
    exit 1
    ;;
esac

fail=0
for repo in "${REPOS[@]}"; do
  echo "setting ${repo} ..."
  if printf '%s' "${PAT}" | gh secret set "${SECRET_NAME}" --repo "${repo}"; then
    meta="$(gh api "repos/${repo}/actions/secrets/${SECRET_NAME}" --jq '{name,updated_at}')"
    echo "  OK  ${meta}"
  else
    echo "  FAIL ${repo}" >&2
    fail=1
  fi
done

unset PAT

echo
echo "=== ${SECRET_NAME} on all listed repos ==="
for repo in "${REPOS[@]}"; do
  printf '%-42s ' "${repo}"
  gh secret list -R "${repo}" 2>/dev/null | awk -v n="${SECRET_NAME}" '$1==n { print; found=1 } END { if (!found) print "MISSING" }'
done

if (( fail )); then
  echo "one or more repos failed" >&2
  exit 1
fi
echo "done."
