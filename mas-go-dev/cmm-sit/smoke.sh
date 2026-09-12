#!/bin/sh
# Same checks as deploy/prod/smoke.sh; defaults are the SIT published ports.
set -eu

api_base=${1:-http://127.0.0.1:25880}
admin_base=${2:-http://127.0.0.1:25881}

curl --fail --silent --show-error "${api_base}/healthz" | grep -q '"status":"ok"'
curl --fail --silent --show-error "${api_base}/readyz" | grep -q '"status":"ok"'
curl --fail --silent --show-error "${api_base}/v1/meta" | grep -q '"name":"cmm-api"'
curl --fail --silent --show-error "${api_base}/v1/products?page=1&pageSize=1" >/dev/null
curl --fail --silent --show-error "${api_base}/v1/market-quotes" >/dev/null

status=$(curl --silent --output /dev/null --write-out '%{http_code}' "${api_base}/v1/staff/accounts")
[ "${status}" = "401" ]

curl --fail --silent --show-error "${admin_base}/" | grep -q '<div id="root"></div>'
printf 'smoke passed api=%s admin=%s\n' "${api_base}" "${admin_base}"
