"""Home Assistant app overrides for Healthchecks.

Imported last by hc/settings.py. Everything here exists to make one codebase
serve two URL prefixes: Home Assistant ingress mounts the app under
/api/hassio_ingress/<token>/, while the mapped port serves it at /.
"""

import os

# Django's get_script_name() returns FORCE_SCRIPT_NAME when set, and the WSGI
# handler feeds that into set_script_prefix(), so reverse() prefixes every
# generated URL. nginx strips the same prefix off the incoming request. Only
# the ingress uWSGI instance sets this; the direct one runs at the root prefix.
_script_name = os.getenv("HC_FORCE_SCRIPT_NAME", "").rstrip("/")
if _script_name:
    FORCE_SCRIPT_NAME = _script_name

# These two are settings, not reversed URLs, so they get the prefix baked in
# rather than picked up per request. Django can prepend SCRIPT_NAME to a
# relative STATIC_URL, but only on first access, and it caches the result
# (django/conf/__init__.py) - by then Django's app registry has already read
# the setting during import, with no request in sight and the prefix still "/".
# Writing the absolute value per instance sidesteps the ordering entirely, and
# is why one process cannot serve both entrances.
STATIC_URL = f"{_script_name}/static/"
LOGIN_URL = f"{_script_name}/accounts/login/"

# django-compressor's offline manifest is rendered at build time and bakes in
# one fixed URL prefix, so it cannot serve both entrances. Fall through to the
# plain {% static %} tags, which resolve per request.
COMPRESS_ENABLED = False
COMPRESS_OFFLINE = False

# Ingress renders the app in an iframe on the Home Assistant origin, and
# Django defaults to DENY.
X_FRAME_OPTIONS = "SAMEORIGIN"

# The Host header is the Home Assistant host under ingress and the app host
# on the direct port. SITE_ROOT, not this, is what the ping URLs are built from.
ALLOWED_HOSTS = ["*"]

# Home Assistant terminates TLS in front of ingress and forwards the original
# scheme. Without this Django sees plain HTTP and rejects POSTs from an HTTPS
# frontend on the CSRF origin check.
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")

_csrf_origins = os.getenv("HC_CSRF_TRUSTED_ORIGINS")
if _csrf_origins:
    CSRF_TRUSTED_ORIGINS = _csrf_origins.split(",")

# Upstream logs to a database handler only. Mirror the app's log level onto
# the container log too, so a problem is visible without opening the web UI.
_log_level = os.getenv("HC_LOG_LEVEL", "INFO").upper()
LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "handlers": {
        "db": {"level": "DEBUG", "class": "hc.logs.Handler"},
        "console": {"level": _log_level, "class": "logging.StreamHandler"},
    },
    "loggers": {
        "django.request": {"level": "ERROR", "handlers": ["db", "console"]},
        "hc": {"level": _log_level, "handlers": ["db", "console"]},
    },
}
