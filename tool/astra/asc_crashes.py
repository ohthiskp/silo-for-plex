#!/usr/bin/env python3
"""Print the newest TestFlight crash reports (sent with Send Beta Feedback).

Env: ASC_KEY_PATH, KEY_ID, ISSUER_ID, BUNDLE_ID. Writes each log to
$RUNNER_TEMP/crashes/ and prints the top of each one. Crash logs can hold the
device name and model, so the workflow keeps them as a short-lived artifact.
"""
import json
import os
import pathlib
import time
import urllib.error
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com/v1"


def token():
    key = open(os.environ["ASC_KEY_PATH"]).read()
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ISSUER_ID"], "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
        key, algorithm="ES256", headers={"kid": os.environ["KEY_ID"], "typ": "JWT"},
    )


def get(path):
    req = urllib.request.Request(API + path, headers={"Authorization": "Bearer " + token()})
    try:
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        raise SystemExit(f"::error::GET {path} failed ({e.code}): {e.read().decode(errors='replace')[:600]}")


apps = get(f"/apps?filter[bundleId]={os.environ['BUNDLE_ID']}")["data"]
if not apps:
    raise SystemExit("::error::No App Store Connect app for " + os.environ["BUNDLE_ID"])
subs = get(f"/apps/{apps[0]['id']}/betaFeedbackCrashSubmissions?sort=-createdDate&limit=5")["data"]
print(f"{len(subs)} crash submission(s)")
out = pathlib.Path(os.environ.get("RUNNER_TEMP", "/tmp")) / "crashes"
out.mkdir(parents=True, exist_ok=True)
for s in subs:
    a = s["attributes"]
    print(f"=== {a.get('createdDate')} build {a.get('buildBundleId', '')} os {a.get('osVersion')} "
          f"device {a.get('deviceModel')} comment: {a.get('comment')!r}")
    try:
        log = get(f"/betaFeedbackCrashSubmissions/{s['id']}/crashLog")["data"]["attributes"].get("logText", "")
    except SystemExit as e:
        print(e)
        continue
    (out / f"{s['id']}.crash").write_text(log)
    lines = log.splitlines()
    keep = [l for l in lines if not l.startswith(("Hardware Model", "Device", "Incident Identifier", "CrashReporter Key", "Beta Identifier"))]
    print("\n".join(keep[:140]))
