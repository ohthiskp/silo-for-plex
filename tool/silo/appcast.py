#!/usr/bin/env python3
"""Sign an Astra macOS DMG for Sparkle and write appcast.xml.

Usage: appcast.py <dmg> <short_version> <build_number> <download_url> <out_dir>
Needs SPARKLE_ED_SEED (base64 Ed25519 seed) in the environment. The matching
public key is SUPublicEDKey in macos/Runner/Info.plist.
"""
import base64
import datetime
import html
import os
import sys

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

dmg, short, build, url, out_dir = sys.argv[1:6]
seed = base64.b64decode(os.environ["SPARKLE_ED_SEED"].strip())
key = Ed25519PrivateKey.from_private_bytes(seed)
data = open(dmg, "rb").read()
sig = base64.b64encode(key.sign(data)).decode()
notes_url = os.environ.get("RELEASE_NOTES_URL", "")
pub = datetime.datetime.now(datetime.timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")

xml = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Astra</title>
    <item>
      <title>Astra {html.escape(short)}</title>
      <pubDate>{pub}</pubDate>
      <sparkle:version>{html.escape(build)}</sparkle:version>
      <sparkle:shortVersionString>{html.escape(short)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      {f'<sparkle:releaseNotesLink>{html.escape(notes_url)}</sparkle:releaseNotesLink>' if notes_url else ''}
      <enclosure url="{html.escape(url)}" length="{len(data)}" type="application/octet-stream" sparkle:edSignature="{sig}"/>
    </item>
  </channel>
</rss>
"""
os.makedirs(out_dir, exist_ok=True)
open(os.path.join(out_dir, "appcast.xml"), "w").write(xml)
print("appcast written for build", build)
