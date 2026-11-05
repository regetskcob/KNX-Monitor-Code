#!/usr/bin/env python3
"""Uploads an App Bundle to a Google Play track with its release notes.

Standard library plus the openssl command line (for the RS256 signature of
the service account token), so no fastlane, Ruby or Google client library is
needed. Called by `werkbank upload-play`.

    play_upload.py --key <service-account.json> --package <id> --aab <file>
                   --track <internal|alpha|beta|production> [--status completed|draft]
                   [--notes <play-notes file>] [--dry-run]

The notes file holds one block per language, as the Play Console takes them:
<de-DE>…</de-DE> <en-US>…</en-US>, each at most 500 characters.
"""

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request

API = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications"
UPLOAD = "https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications"
SCOPE = "https://www.googleapis.com/auth/androidpublisher"


def parse_notes(text, langs=()):
    """Language → text from <xx-YY>…</xx-YY> blocks; fails on a block over 500 characters
    and when one of [langs] (the store languages) has no block."""
    notes = {}
    for lang, body in re.findall(r"<([a-z]{2}-[A-Z]{2})>\s*(.*?)\s*</\1>", text, re.S):
        if len(body) > 500:
            raise SystemExit(f"error: release notes {lang} have {len(body)} characters, Play takes 500")
        notes[lang] = body
    if not notes:
        raise SystemExit("error: no <de-DE>…</de-DE> blocks in the release notes")
    missing = [l for l in langs if l not in notes]
    if missing:
        raise SystemExit(f"error: release notes miss {', '.join(missing)}")
    return notes


def b64(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def token(key):
    """OAuth access token for the service account (JWT bearer grant)."""
    now = int(time.time())
    header = b64(json.dumps({"alg": "RS256", "typ": "JWT"}).encode())
    claims = b64(json.dumps({
        "iss": key["client_email"], "scope": SCOPE, "aud": key["token_uri"], "iat": now, "exp": now + 3600,
    }).encode())
    signing = f"{header}.{claims}".encode()
    # The private key only ever lives in a file readable by the user, removed right after.
    fd, pem = tempfile.mkstemp(suffix=".pem")
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w") as f:
            f.write(key["private_key"])
        sig = subprocess.run(["openssl", "dgst", "-sha256", "-sign", pem], input=signing,
                             capture_output=True, check=True).stdout
    finally:
        os.remove(pem)
    body = urllib.parse.urlencode({
        "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
        "assertion": f"{signing.decode()}.{b64(sig)}",
    }).encode()
    with urllib.request.urlopen(urllib.request.Request(key["token_uri"], data=body), timeout=60) as r:
        return json.load(r)["access_token"]


def call(method, url, tok, body=None, data=None, ctype="application/json"):
    req = urllib.request.Request(url, method=method, headers={"Authorization": f"Bearer {tok}"})
    if body is not None:
        req.data = json.dumps(body).encode()
        req.add_header("Content-Type", "application/json")
    elif data is not None:
        req.data = data
        req.add_header("Content-Type", ctype)
    try:
        with urllib.request.urlopen(req, timeout=600) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        raise SystemExit(f"error: Play {method} {url.split('/applications/')[-1]}: {e.code} {e.read().decode()[:400]}")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--key", required=True)
    p.add_argument("--package", required=True)
    p.add_argument("--aab", required=True)
    p.add_argument("--track", default="internal")
    p.add_argument("--status", default="completed", choices=["completed", "draft"])
    p.add_argument("--notes")
    p.add_argument("--langs", default="", help="store languages that must have notes, space separated")
    p.add_argument("--dry-run", action="store_true")
    a = p.parse_args()
    if not re.fullmatch(r"[a-zA-Z][\w.]+", a.package):
        raise SystemExit(f"error: bad package name {a.package}")
    notes = parse_notes(open(a.notes, encoding="utf-8").read(), a.langs.split()) if a.notes else {}
    if not os.path.isfile(a.aab):
        raise SystemExit(f"error: {a.aab} missing")
    plan = f"{a.aab} → {a.package}, track {a.track} ({a.status}), notes: {', '.join(notes) or 'none'}"
    if a.dry_run:
        print(f"would upload {plan}")
        return
    key = json.load(open(a.key, encoding="utf-8"))
    tok = token(key)
    edit = call("POST", f"{API}/{a.package}/edits", tok, body={})["id"]
    with open(a.aab, "rb") as f:
        bundle = call("POST", f"{UPLOAD}/{a.package}/edits/{edit}/bundles?uploadType=media", tok,
                      data=f.read(), ctype="application/octet-stream")
    code = str(bundle["versionCode"])
    release = {"versionCodes": [code], "status": a.status}
    if notes:
        release["releaseNotes"] = [{"language": k, "text": v} for k, v in notes.items()]
    call("PUT", f"{API}/{a.package}/edits/{edit}/tracks/{a.track}", tok, body={"track": a.track, "releases": [release]})
    call("POST", f"{API}/{a.package}/edits/{edit}:commit", tok, body={})
    print(f"uploaded versionCode {code}: {plan}")


if __name__ == "__main__":
    sys.exit(main())
