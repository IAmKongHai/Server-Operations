#!/usr/bin/env python3
import json
import urllib.error
import urllib.request

acct = {}
with open("/opt/evp-sit/accounts.env") as fh:
    for line in fh:
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        acct[key] = value


def login(origin, prefix, user, password, cookie_name):
    req = urllib.request.Request(
        origin + prefix + "/auth/login",
        data=json.dumps({"username": user, "password": password}).encode(),
        method="POST",
        headers={"Content-Type": "application/json", "Origin": origin},
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        body = json.loads(resp.read().decode())
        cookie = resp.headers.get("Set-Cookie", "")
        user_name = body.get("username")
        if user_name is None and isinstance(body.get("user"), dict):
            user_name = body["user"].get("username")
        print(prefix, "login", resp.status, "user", user_name, "cookie", cookie_name in cookie)
        if cookie_name not in cookie:
            raise SystemExit("missing session cookie")


login(
    "http://100.109.223.53:25173",
    "/api/provider/v1",
    acct["EVP_PROVIDER_USERNAME"],
    acct["EVP_PROVIDER_PASSWORD"],
    "evp_provider_session",
)
login(
    "http://100.109.223.53:25174",
    "/api/admin/v1",
    acct["EVP_ADMIN_USERNAME"],
    acct["EVP_ADMIN_PASSWORD"],
    "evp_admin_session",
)

req = urllib.request.Request(
    "http://100.109.223.53:25173/api/provider/v1/auth/login",
    data=json.dumps({"username": "x", "password": "y"}).encode(),
    method="POST",
    headers={"Content-Type": "application/json"},
)
try:
    urllib.request.urlopen(req, timeout=10)
    raise SystemExit("missing origin unexpectedly succeeded")
except urllib.error.HTTPError as err:
    print("missing origin", err.code)
