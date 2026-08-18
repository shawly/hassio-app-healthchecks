#!/usr/bin/env bash
# ==============================================================================
# Home Assistant App: Healthchecks
#
# Boots the app image against a mock Supervisor API and exercises both
# entrances. The point of this suite is the pair of assertions about asset
# URLs: Django caches the script prefix into STATIC_URL on first access, so a
# single shared process would get one of the two prefixes wrong.
# ==============================================================================
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

readonly IMAGE="local/hassio-addon-healthchecks:test"
readonly IMAGE_CURL="curlimages/curl:8.18.0"
readonly NETWORK="healthchecks-addon-test"
readonly SUPERVISOR="healthchecks-test-supervisor"
readonly ADDON="healthchecks-test-addon"
readonly CLIENT="healthchecks-test-client"
# The Supervisor always proxies ingress from this address, and nginx only
# accepts ingress requests from it. Recreating that here keeps the deny rule
# under test instead of working around it.
readonly SUPERVISOR_SUBNET="172.30.32.0/24"
readonly SUPERVISOR_IP="172.30.32.2"
# Docker hands out addresses from the start of the subnet, so keep automatic
# assignment in the upper half and leave the Supervisor address free.
readonly SUPERVISOR_POOL="172.30.32.128/25"
readonly INGRESS_ENTRY="/api/hassio_ingress/testtoken"
readonly INGRESS_PORT=11337
readonly DIRECT_PORT=18000
readonly SUPERVISOR_TOKEN="test-supervisor-token"
readonly SUPERUSER_EMAIL="e2e@example.com"
readonly SUPERUSER_PASSWORD="e2e-test-password"
# Healthchecks rejects anything that is not exactly 32 characters.
readonly API_KEY="e2e0123456789abcdef0123456789abc"

KEEP=false
SKIP_BUILD=false
DATA_DIR=""

for arg in "$@"; do
    case "${arg}" in
        --keep) KEEP=true ;;
        --skip-build) SKIP_BUILD=true ;;
        *) bail "unknown argument: ${arg}" ;;
    esac
done

cleanup() {
    local status=$?
    if [[ "${status}" -ne 0 || "${TESTS_FAILED}" -ne 0 ]]; then
        log::step "App log"
        docker logs "${ADDON}" 2>&1 | tail -80 || true
    fi
    if [[ "${KEEP}" == true ]]; then
        log::info "leaving containers up (--keep)"
        return
    fi
    docker rm -f "${ADDON}" "${SUPERVISOR}" "${CLIENT}" > /dev/null 2>&1 || true
    docker network rm "${NETWORK}" > /dev/null 2>&1 || true
    [[ -n "${DATA_DIR}" ]] && rm -rf "${DATA_DIR}"
    return 0
}
trap cleanup EXIT

require::docker
cd "${REPO_ROOT}"

# ------------------------------------------------------------------------------
# Build
# ------------------------------------------------------------------------------
if [[ "${SKIP_BUILD}" == false ]]; then
    log::step "Building the app image"
    docker build \
        --build-arg BUILD_FROM="ghcr.io/hassio-addons/base:21.0.2" \
        --build-arg BUILD_ARCH="amd64" \
        --build-arg BUILD_VERSION="test" \
        --build-arg BUILD_NAME="Healthchecks" \
        --build-arg BUILD_DESCRIPTION="Test build" \
        --build-arg BUILD_REPOSITORY="shawly/hassio-app-healthchecks" \
        --build-arg BUILD_REF="0000000" \
        --build-arg BUILD_DATE="1970-01-01T00:00:00Z" \
        --tag "${IMAGE}" \
        healthchecks > /dev/null \
        || bail "the image failed to build"
    assert::ok "image builds"
fi

# ------------------------------------------------------------------------------
# Boot
# ------------------------------------------------------------------------------
log::step "Starting the app against a mock Supervisor"
docker rm -f "${ADDON}" "${SUPERVISOR}" "${CLIENT}" > /dev/null 2>&1 || true
docker network rm "${NETWORK}" > /dev/null 2>&1 || true
docker network create --subnet "${SUPERVISOR_SUBNET}" \
    --ip-range "${SUPERVISOR_POOL}" "${NETWORK}" > /dev/null

DATA_DIR=$(mktemp -d)
chmod 777 "${DATA_DIR}"

options=$(jq -nc \
    --arg email "${SUPERUSER_EMAIL}" \
    --arg password "${SUPERUSER_PASSWORD}" \
    --arg site_root "http://localhost:${DIRECT_PORT}" \
    '{
        log_level: "debug",
        site_name: "Healthchecks",
        site_root: $site_root,
        registration_open: false,
        allow_private_ips: true,
        db: "sqlite",
        superuser_email: $email,
        superuser_password: $password,
        csrf_trusted_origins: [],
        ssl: false,
        certfile: "fullchain.pem",
        keyfile: "privkey.pem"
    }')

docker run -d --name "${SUPERVISOR}" \
    --network "${NETWORK}" --network-alias supervisor \
    -v "${PWD}/tests/mock-supervisor.py:/mock-supervisor.py:ro" \
    -e INGRESS_ENTRY="${INGRESS_ENTRY}" \
    -e ADDON_OPTIONS="${options}" \
    -e PORT_8000="8000" \
    python:3.13-alpine python /mock-supervisor.py > /dev/null

# Stands in for the Supervisor's ingress proxy: same network, same source IP.
docker run -d --name "${CLIENT}" \
    --network "${NETWORK}" --ip "${SUPERVISOR_IP}" \
    --entrypoint sleep "${IMAGE_CURL}" infinity > /dev/null

# Every ingress request has to come from the Supervisor address, so it goes
# through the client container rather than the published port.
ingress_curl() {
    docker exec "${CLIENT}" curl "$@"
}

# bashio queries the Supervisor before the app has served a single request,
# so the mock has to be answering before the app starts.
supervisor_ready=false
for _ in $(seq 1 30); do
    if ingress_curl -fsS -o /dev/null "http://supervisor/supervisor/ping" \
        2> /dev/null; then
        supervisor_ready=true
        break
    fi
    sleep 1
done
[[ "${supervisor_ready}" == true ]] || bail "the mock Supervisor never came up"

docker run -d --name "${ADDON}" \
    --network "${NETWORK}" --network-alias addon \
    -e SUPERVISOR_TOKEN="${SUPERVISOR_TOKEN}" \
    -v "${DATA_DIR}:/data" \
    -p "127.0.0.1:${INGRESS_PORT}:1337" \
    -p "127.0.0.1:${DIRECT_PORT}:8000" \
    "${IMAGE}" > /dev/null

log::info "waiting for the app to come up"
ready=false
for _ in $(seq 1 90); do
    if ingress_curl -fsS -o /dev/null "http://addon:1337${INGRESS_ENTRY}/" \
        2> /dev/null; then
        ready=true
        break
    fi
    if ! docker ps --format '{{.Names}}' | grep -qx "${ADDON}"; then
        break
    fi
    sleep 2
done

if [[ "${ready}" == true ]]; then
    assert::ok "app serves the ingress entry point"
else
    assert::fail "app serves the ingress entry point" "it never became ready"
    assert::summary
    exit 1
fi

ingress_url="http://addon:1337${INGRESS_ENTRY}"
direct_url="http://localhost:${DIRECT_PORT}"

# ------------------------------------------------------------------------------
# Ingress entrance
# ------------------------------------------------------------------------------
log::step "Ingress entrance"

ingress_html=$(ingress_curl -fsSL "${ingress_url}/")
assert::contains "ingress serves the sign-in page" "${ingress_html}" "csrfmiddlewaretoken"

# The whole reason this app runs two uWSGI instances. If both entrances
# shared a process, one of these two blocks would fail.
assert::contains "ingress asset URLs carry the ingress prefix" \
    "${ingress_html}" "${INGRESS_ENTRY}/static/"
assert::not_contains "ingress asset URLs are not root-absolute" \
    "${ingress_html}" '="/static/'

css_path=$(grep -o "${INGRESS_ENTRY}/static/[^\"']*\.css" <<< "${ingress_html}" \
    | head -1)
if [[ -n "${css_path}" ]]; then
    css_type=$(ingress_curl -fsS -o /dev/null -w '%{content_type}' \
        "http://addon:1337${css_path}" || echo "")
    assert::contains "ingress stylesheet is served" "${css_type}" "text/css"
else
    assert::fail "ingress stylesheet is served" "no stylesheet link in the HTML"
fi

xfo=$(ingress_curl -fsSL -o /dev/null -D - "${ingress_url}/accounts/login/" | grep -i "^x-frame-options:" \
    | tr -d '\r' | awk '{print $2}')
assert::equals "ingress allows the Home Assistant iframe" "SAMEORIGIN" "${xfo}"

redirect=$(ingress_curl -s -o /dev/null -w '%{http_code}' \
    "http://addon:1337${INGRESS_ENTRY}")
assert::equals "ingress entry without a trailing slash redirects" "301" "${redirect}"

off_prefix=$(ingress_curl -s -o /dev/null -w '%{http_code}' "http://addon:1337/")
assert::equals "ingress port serves nothing outside its prefix" "404" "${off_prefix}"

# The published port reaches nginx from the bridge gateway, not the Supervisor.
denied=$(curl -s -o /dev/null -w '%{http_code}' \
    "http://localhost:${INGRESS_PORT}${INGRESS_ENTRY}/")
assert::equals "ingress rejects requests from anywhere but the Supervisor" \
    "403" "${denied}"

# ------------------------------------------------------------------------------
# Direct entrance
# ------------------------------------------------------------------------------
log::step "Direct entrance"

direct_html=$(curl -fsSL "${direct_url}/")
assert::contains "direct port serves the sign-in page" \
    "${direct_html}" "csrfmiddlewaretoken"
assert::contains "direct asset URLs are root-absolute" "${direct_html}" '="/static/'
assert::not_contains "direct asset URLs do not carry the ingress prefix" \
    "${direct_html}" "${INGRESS_ENTRY}"

css_path=$(grep -o '"/static/[^"]*\.css"' <<< "${direct_html}" | head -1 | tr -d '"')
if [[ -n "${css_path}" ]]; then
    css_type=$(curl -fsS -o /dev/null -w '%{content_type}' \
        "${direct_url}${css_path}" || echo "")
    assert::contains "direct stylesheet is served" "${css_type}" "text/css"
else
    assert::fail "direct stylesheet is served" "no stylesheet link in the HTML"
fi

# ------------------------------------------------------------------------------
# Sign-in, which is where a broken CSRF origin check shows up
# ------------------------------------------------------------------------------
log::step "Sign in through ingress"

cookies="/tmp/cookies.txt"
csrf=$(ingress_curl -fsS -c "${cookies}" "${ingress_url}/accounts/login/" \
    | grep -o 'name="csrfmiddlewaretoken" value="[^"]*"' \
    | head -1 | cut -d'"' -f4)

# X-Forwarded-Proto says https while nginx and Django speak plain HTTP, which is
# the shape of a real ingress request. Without SECURE_PROXY_SSL_HEADER, Django
# compares the Origin against http://<host> and rejects this with a 403.
login_code=$(ingress_curl -s -o /dev/null -w '%{http_code}' \
    -b "${cookies}" -c "${cookies}" \
    -H "Origin: https://addon:1337" \
    -H "Referer: https://addon:1337${INGRESS_ENTRY}/accounts/login/" \
    -H "X-Forwarded-Proto: https" \
    -H "X-Forwarded-For: 172.30.32.2" \
    --data-urlencode "csrfmiddlewaretoken=${csrf}" \
    --data-urlencode "email=${SUPERUSER_EMAIL}" \
    --data-urlencode "password=${SUPERUSER_PASSWORD}" \
    --data-urlencode "action=login" \
    "${ingress_url}/accounts/login/")
assert::not_contains "an HTTPS-origin POST is not rejected by the CSRF check" \
    "${login_code}" "403"

profile=$(ingress_curl -fsSL -b "${cookies}" "${ingress_url}/accounts/profile/" \
    || echo "")
assert::contains "the superuser from the app options can sign in" \
    "${profile}" "${SUPERUSER_EMAIL}"

# ------------------------------------------------------------------------------
# Pings, the reason the direct port exists at all
# ------------------------------------------------------------------------------
log::step "Ping round trip"

# Healthchecks only hands out API keys through the web interface, so reach into
# the running instance instead of scripting a browser session.
api_key_script=$(printf '%s\n' \
    "import os" \
    "from hc.accounts.models import Project" \
    "p = Project.objects.get(owner__email=os.environ['HC_EMAIL'])" \
    "p.api_key = os.environ['HC_API_KEY']" \
    "p.save()")

docker exec -i -e HC_API_KEY="${API_KEY}" -e HC_EMAIL="${SUPERUSER_EMAIL}" \
    -e HC_SCRIPT="${api_key_script}" -w /opt/healthchecks "${ADDON}" \
    /bin/bash -c 'set -a; source /var/run/healthchecks/env; set +a;
     printf "%s" "${HC_SCRIPT}" | /opt/venv/bin/python manage.py shell' \
    || bail "could not set an API key for the test project"

created=$(curl -fsS -X POST "${direct_url}/api/v3/checks/" \
    -H "X-Api-Key: ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"name": "e2e", "timeout": 3600, "grace": 60}' || echo "")
assert::contains "a check can be created over the API" "${created}" '"ping_url"'

ping_url=$(jq -r '.ping_url // empty' <<< "${created}")
if [[ -n "${ping_url}" ]]; then
    ping_code=$(curl -s -o /dev/null -w '%{http_code}' "${ping_url}")
    assert::equals "the ping URL answers" "200" "${ping_code}"

    # A new account already has a "My First Check", so select by name.
    status=$(curl -fsS "${direct_url}/api/v3/checks/" -H "X-Api-Key: ${API_KEY}" \
        | jq -r '.checks[] | select(.name == "e2e") | .status')
    assert::equals "the ping flipped the check to up" "up" "${status}"
else
    assert::fail "the ping URL answers" "no ping_url in the API response"
    assert::fail "the ping flipped the check to up" "no ping_url in the API response"
fi

assert::contains "the ping URL points at the configured site_root" \
    "${ping_url}" "http://localhost:${DIRECT_PORT}/ping/"

# ------------------------------------------------------------------------------
# Persistence
# ------------------------------------------------------------------------------
log::step "Persistence across a restart"

if [[ -f "${DATA_DIR}/healthchecks.sqlite" ]]; then
    assert::ok "the database lives in /data"
else
    assert::fail "the database lives in /data" "no healthchecks.sqlite in the volume"
fi
if [[ -f "${DATA_DIR}/secret_key" ]]; then
    assert::ok "the secret key lives in /data"
else
    assert::fail "the secret key lives in /data" "no secret_key in the volume"
fi
# Root-owned and mode 600 inside the container, so read it from there.
secret_before=$(docker exec "${ADDON}" cat /data/secret_key)

docker restart "${ADDON}" > /dev/null
for _ in $(seq 1 60); do
    curl -fsS -o /dev/null "${direct_url}/" 2> /dev/null && break
    sleep 2
done

after=$(curl -fsS "${direct_url}/api/v3/checks/" -H "X-Api-Key: ${API_KEY}" \
    | jq -r '[.checks[] | select(.name == "e2e") | .name][0] // empty' || echo "")
assert::equals "the check survives a restart" "e2e" "${after}"
assert::equals "the secret key is not regenerated" \
    "${secret_before}" "$(docker exec "${ADDON}" cat /data/secret_key)"

assert::summary
