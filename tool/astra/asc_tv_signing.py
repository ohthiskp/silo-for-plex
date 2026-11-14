#!/usr/bin/env python3
"""Temporary App Store signing for the Apple TV build (and the SwiftUI iPhone
build), via the App Store Connect API.

Defaults are the Flutter Apple TV app. The SwiftUI iPhone workflow sets
ASTRA_SIGNING_PLATFORM=IOS and ASTRA_SIGNING_TARGETS="com.ohthiskp.astra=AstraiOS".

  asc_tv_signing.py setup    -> creates a distribution certificate + tvOS App Store
                                profiles, installs them in a throwaway keychain and
                                writes ids/names to $RUNNER_TEMP/tv_signing.json
  asc_tv_signing.py cleanup  -> deletes the profiles and revokes the certificate

Before creating anything, setup removes what an earlier run left behind (a run
whose cleanup never happened: lost runner, API error). Those are recognised by
this script's profile names ("Astra <platform> <target> <UTC stamp>") older
than STALE_HOURS, so a run that is still going is never touched. Apple allows
only a few distribution certificates, so leftovers would otherwise block uploads.

Needs ASC_KEY_PATH, KEY_ID, ISSUER_ID, TEAM_ID in the environment (set by the
workflow's "Write API key" step). The team has no registered Apple TV, so the
automatic development-profile route is not available; App Store profiles need
no devices.
"""
import base64
import datetime
import json
import os
import pathlib
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

import jwt
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID

API = "https://api.appstoreconnect.apple.com/v1"
TARGETS = {  # bundle id -> Xcode target
    "com.ohthiskp.astra": "Runner",
    "com.ohthiskp.astra.TopShelfExtension": "TopShelfExtension",
}
if os.environ.get("ASTRA_SIGNING_TARGETS"):
    TARGETS = dict(pair.split("=", 1) for pair in os.environ["ASTRA_SIGNING_TARGETS"].split(","))
PLATFORM = os.environ.get("ASTRA_SIGNING_PLATFORM", "TVOS")  # TVOS or IOS
PROFILE_TYPE = {"TVOS": "TVOS_APP_STORE", "IOS": "IOS_APP_STORE"}[PLATFORM]
STATE = pathlib.Path(os.environ.get("RUNNER_TEMP", "/tmp")) / "tv_signing.json"
KEYCHAIN = pathlib.Path(os.environ.get("RUNNER_TEMP", "/tmp")) / "astra-signing.keychain-db"
# Jobs time out after 60 min; anything this old is a leftover, never a run in progress.
STALE_HOURS = 3
PROFILE_NAME = re.compile(r"^Astra (tvos|ios) \S+ (\d{14})$")


def token():
    key = open(os.environ["ASC_KEY_PATH"]).read()
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ISSUER_ID"], "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"},
        key, algorithm="ES256", headers={"kid": os.environ["KEY_ID"], "typ": "JWT"},
    )


def call(method, path, body=None):
    req = urllib.request.Request(
        API + path, method=method,
        data=None if body is None else json.dumps(body).encode(),
        headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")[:800]
        raise SystemExit(f"::error::App Store Connect {method} {path} failed ({e.code}): {detail}")


def bundle_id(identifier):
    found = call("GET", f"/bundleIds?filter[identifier]={identifier}&limit=200").get("data", [])
    for b in found:
        if b["attributes"]["identifier"] == identifier:
            return b["id"]
    print(f"Registering app ID {identifier}")
    made = call("POST", "/bundleIds", {"data": {"type": "bundleIds", "attributes": {
        "identifier": identifier, "name": "Astra " + identifier.split(".")[-1], "platform": "IOS"}}})
    return made["data"]["id"]


def sh(*args):
    subprocess.run(args, check=True)


def remove_leftovers(now=None):
    """Deletes this script's profiles older than STALE_HOURS and revokes their certificates."""
    now = now or datetime.datetime.now(datetime.timezone.utc)
    try:
        listing = call("GET", "/profiles?limit=200&include=certificates")
    except SystemExit as e:
        # Never block a build over housekeeping.
        print(str(e).replace("::error::", "::warning::Couldn't look for leftovers: "))
        return
    stale_certs, removed = set(), 0
    for p in listing.get("data", []):
        name = p.get("attributes", {}).get("name", "")
        if not is_stale(name, now):
            continue
        for c in p.get("relationships", {}).get("certificates", {}).get("data", []) or []:
            stale_certs.add(c["id"])
        try:
            call("DELETE", f"/profiles/{p['id']}")
            removed += 1
            print(f"Removed leftover profile {name}")
        except SystemExit as e:
            print(str(e).replace("::error::", "::warning::"))
    for cid in sorted(stale_certs):
        try:
            call("DELETE", f"/certificates/{cid}")
            print(f"Revoked leftover distribution certificate {cid}")
        except SystemExit as e:
            print(str(e).replace("::error::", "::warning::"))
    if not removed and not stale_certs:
        print("No leftovers from earlier runs.")


def is_stale(name, now):
    m = PROFILE_NAME.match(name)
    if not m:
        return False
    made = datetime.datetime.strptime(m.group(2), "%Y%m%d%H%M%S").replace(tzinfo=datetime.timezone.utc)
    return now - made > datetime.timedelta(hours=STALE_HOURS)


def setup():
    remove_leftovers()
    # 1. key + CSR -> distribution certificate
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    csr = (x509.CertificateSigningRequestBuilder()
           .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Astra CI"),
                                    x509.NameAttribute(NameOID.EMAIL_ADDRESS, "noreply@example.com")]))
           .sign(key, hashes.SHA256()))
    csr_b64 = base64.b64encode(csr.public_bytes(serialization.Encoding.DER)).decode()
    cert_resp = call("POST", "/certificates", {"data": {"type": "certificates", "attributes": {
        "csrContent": csr_b64, "certificateType": "DISTRIBUTION"}}})
    cert_id = cert_resp["data"]["id"]
    cert = x509.load_der_x509_certificate(base64.b64decode(cert_resp["data"]["attributes"]["certificateContent"]))
    state = {"certificate": cert_id, "profiles": {}}
    STATE.write_text(json.dumps(state))
    print(f"Created distribution certificate {cert_id}")

    # 2. throwaway keychain with the identity (3DES/SHA1 p12 so macOS `security` accepts it)
    password = base64.b64encode(os.urandom(18)).decode()
    enc = (serialization.PrivateFormat.PKCS12.encryption_builder()
           .kdf_rounds(50000)
           .key_cert_algorithm(pkcs12.PBES.PBESv1SHA1And3KeyTripleDESCBC)
           .hmac_hash(hashes.SHA1())
           .build(password.encode()))
    p12 = pathlib.Path(os.environ.get("RUNNER_TEMP", "/tmp")) / "astra-dist.p12"
    p12.write_bytes(pkcs12.serialize_key_and_certificates(b"Astra CI", key, cert, None, enc))
    kc_pw = base64.b64encode(os.urandom(18)).decode()
    sh("security", "create-keychain", "-p", kc_pw, str(KEYCHAIN))
    sh("security", "set-keychain-settings", "-lut", "21600", str(KEYCHAIN))
    sh("security", "unlock-keychain", "-p", kc_pw, str(KEYCHAIN))
    sh("security", "import", str(p12), "-k", str(KEYCHAIN), "-P", password, "-T", "/usr/bin/codesign", "-T", "/usr/bin/security")
    sh("security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:", "-s", "-k", kc_pw, str(KEYCHAIN))
    existing = subprocess.run(["security", "list-keychains", "-d", "user"], capture_output=True, text=True).stdout
    sh("security", "list-keychains", "-d", "user", "-s", str(KEYCHAIN),
       *[k.strip().strip('"') for k in existing.split() if k.strip()])
    p12.unlink()

    # 3. one App Store profile per target
    dirs = [pathlib.Path.home() / "Library/MobileDevice/Provisioning Profiles",
            pathlib.Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles"]
    for d in dirs:
        d.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%d%H%M%S", time.gmtime())  # UTC: remove_leftovers reads it back
    for identifier, target in TARGETS.items():
        bid = bundle_id(identifier)
        name = f"Astra {PLATFORM.lower()} {target} {stamp}"
        prof = call("POST", "/profiles", {"data": {"type": "profiles",
            "attributes": {"name": name, "profileType": PROFILE_TYPE},
            "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bid}},
                              "certificates": {"data": [{"type": "certificates", "id": cert_id}]}}}})
        attrs = prof["data"]["attributes"]
        content = base64.b64decode(attrs["profileContent"])
        for d in dirs:
            (d / f"{attrs['uuid']}.mobileprovision").write_bytes(content)
        state["profiles"][identifier] = {"id": prof["data"]["id"], "name": name, "uuid": attrs["uuid"], "target": target}
        STATE.write_text(json.dumps(state))
        print(f"Created profile '{name}' for {identifier}")


def cleanup():
    if not STATE.exists():
        print("Nothing to clean up.")
        return
    state = json.loads(STATE.read_text())
    failed = []
    for p in state.get("profiles", {}).values():
        if retry(lambda: call("DELETE", f"/profiles/{p['id']}")):
            print(f"Deleted profile {p['name']}")
        else:
            failed.append(f"profile {p['name']} ({p['id']})")
    if state.get("certificate"):
        if retry(lambda: call("DELETE", f"/certificates/{state['certificate']}")):
            print("Revoked the temporary distribution certificate")
        else:
            failed.append(f"distribution certificate {state['certificate']}")
    subprocess.run(["security", "delete-keychain", str(KEYCHAIN)])
    if failed:
        # The build itself is fine; the next run's setup removes these once they're old.
        print("::warning::Temporary signing wasn't fully removed: " + ", ".join(failed)
              + ". The next run removes them; or revoke them at developer.apple.com/account/resources/certificates.")
        sys.exit(1)


def retry(action, attempts=3):
    for attempt in range(1, attempts + 1):
        try:
            action()
            return True
        except SystemExit as e:
            print(str(e).replace("::error::", ""))
            if attempt < attempts:
                time.sleep(5 * attempt)
    return False


if __name__ == "__main__":
    {"setup": setup, "cleanup": cleanup}[sys.argv[1]]()
