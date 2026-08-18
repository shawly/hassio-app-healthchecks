#!/usr/bin/env python3
"""Take the ingress prefix back off Healthchecks' absolute URLs.

Healthchecks builds absolute URLs as SITE_ROOT + reverse(), and reverse()
prefixes every path with FORCE_SCRIPT_NAME, which for the ingress instance is
the ingress entry point. That produces URLs like

    http://homeassistant:8000/api/hassio_ingress/<token>/badge/<key>.svg

for status badges, e-mail links, OAuth redirect URIs and the site logo handed
to Slack: the host of the mapped port, where the app is served at the root,
glued to a path that only exists behind ingress. It also puts the ingress
token in places it does not belong, like a README badge.

Applied at build time, and it fails the build rather than silently doing
nothing if upstream rewrites the function.
"""

from __future__ import annotations

import sys
from pathlib import Path

TARGET = Path("/opt/healthchecks/hc/lib/urls.py")

OLD = '''def absolute_url(path: str) -> str:
    subpath = urlparse(settings.SITE_ROOT).path
    return settings.SITE_ROOT.removesuffix(subpath) + path
'''

NEW = '''def absolute_url(path: str) -> str:
    # Home Assistant app: reverse() prefixes paths with FORCE_SCRIPT_NAME,
    # which is the ingress entry point, while SITE_ROOT points at the mapped
    # port, where the app is served at the root. Drop the prefix before
    # joining the two. See patches/absolute-url-script-name.py.
    if settings.FORCE_SCRIPT_NAME:
        path = path.removeprefix(settings.FORCE_SCRIPT_NAME)

    subpath = urlparse(settings.SITE_ROOT).path
    return settings.SITE_ROOT.removesuffix(subpath) + path
'''

source = TARGET.read_text()
if source.count(OLD) != 1:
    sys.exit(
        f"{TARGET} does not contain the expected absolute_url() body. "
        "Healthchecks changed it upstream; review the patch before bumping "
        "HEALTHCHECKS_VERSION."
    )

TARGET.write_text(source.replace(OLD, NEW))
print(f"patched {TARGET}")
