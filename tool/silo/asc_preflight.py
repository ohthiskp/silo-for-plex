#!/usr/bin/env python3
"""Get App Store Connect ready for an Astra TestFlight upload.

- Registers the bundle ID with Apple if it isn't registered yet.
- Checks that an App Store Connect app record exists for it, and explains
  how to create one if not (Apple's API can't create app records).

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, BUNDLE_ID, PLATFORM (IOS|MAC_OS|UNIVERSAL)
Writes "app_id=<id>" to $GITHUB_OUTPUT when the record exists.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt  # PyJWT

API = "https://api.appstoreconnect.apple.com/v1"


def token():
    key = open(os.environ["ASC_KEY_PATH"]).read()
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
        key,
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )


def call(method, path, body=None):
    req = urllib.request.Request(API + path, method=method)
    req.add_header("Authorization", "Bearer " + token())
    if body is not None:
        req.add_header("Content-Type", "application/json")
        req.data = json.dumps(body).encode()
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


def diagnose():
    """Check the shape of each credential without printing any secret."""
    import re
    from cryptography.hazmat.primitives.serialization import load_pem_private_key
    raw_kid = os.environ.get("ASC_KEY_ID", "")
    raw_iss = os.environ.get("ASC_ISSUER_ID", "")
    kid = re.sub(r"\s", "", raw_kid)
    iss = re.sub(r"\s", "", raw_iss).lower()
    if kid != raw_kid or iss != raw_iss:
        print("::warning::Removed stray spaces from the key/issuer IDs; fine to leave the secrets as they are.")
    os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"] = kid, iss
    ok = True
    if not re.fullmatch(r"[A-Z0-9]{10}", kid):
        print(f"::error::ASC_KEY_ID should be exactly 10 capital letters/digits (got {len(kid)}).")
        ok = False
    if not re.fullmatch(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", iss):
        print(f"::error::ASC_ISSUER_ID should look like 57246542-96fe-1a63-e053-0824d011072a (got {len(iss)} characters). Copy it from the top of the Team Keys page.")
        ok = False
    try:
        k = load_pem_private_key(open(os.environ["ASC_KEY_PATH"], "rb").read(), None)
        print(f"Key file parses as {type(k).__name__} on curve {getattr(getattr(k, 'curve', None), 'name', '?')}.")
    except Exception as e:
        print(f"::error::ASC_KEY_P8 isn't a valid private key ({type(e).__name__}).")
        ok = False
    return ok


def main():
    if not diagnose():
        sys.exit(1)
    bundle = os.environ["BUNDLE_ID"]
    platform = os.environ.get("PLATFORM", "IOS")
    q = urllib.parse.quote(bundle)

    status, res = call("GET", f"/bundleIds?filter[identifier]={q}&limit=5")
    if status == 401:
        print("::error::Apple rejected the API key. The IDs look well-formed, so the usual causes are: "
              "(1) the key was made under Individual Keys instead of Team Keys, "
              "(2) ASC_KEY_ID doesn't belong to the .p8 that was pasted (the file name AuthKey_XXXXXXXXXX.p8 shows its Key ID), or "
              "(3) the key was revoked. Apple said: " + json.dumps(res)[:300])
        sys.exit(1)
    if status != 200:
        print(f"::error::App Store Connect API error {status}: {res}")
        sys.exit(1)
    exact = [d for d in res.get("data", []) if d["attributes"]["identifier"] == bundle]
    if exact:
        print(f"Bundle ID {bundle} is registered.")
    else:
        status, res = call("POST", "/bundleIds", {
            "data": {"type": "bundleIds", "attributes": {"identifier": bundle, "name": "Astra", "platform": platform}}
        })
        if status not in (200, 201):
            print(f"::error::Couldn't register bundle ID {bundle}: {status} {res}")
            sys.exit(1)
        print(f"Registered bundle ID {bundle}.")

    status, res = call("GET", f"/apps?filter[bundleId]={q}&limit=5")
    apps = [a for a in res.get("data", []) if a["attributes"].get("bundleId") == bundle]
    if not apps:
        print(
            "::error::No App Store Connect app exists for "
            f"{bundle} yet. Create it once: appstoreconnect.apple.com → Apps → + → New App → "
            f"platform iOS (and tvOS if you want Apple TV), any unique name, bundle ID {bundle}, SKU astra. "
            "Then run this workflow again."
        )
        sys.exit(1)
    app_id = apps[0]["id"]
    print(f"App record found: {apps[0]['attributes'].get('name')} ({app_id}).")
    out = os.environ.get("GITHUB_OUTPUT")
    if out:
        with open(out, "a") as f:
            f.write(f"app_id={app_id}\n")


if __name__ == "__main__":
    main()
