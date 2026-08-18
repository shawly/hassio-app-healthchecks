#!/usr/bin/env bash
# ==============================================================================
# Home Assistant App: Healthchecks
#
# Runs the same linters the CI workflow does, through Docker so nothing has to
# be installed on the host. A pass here should mean a pass in
# hassio-addons/workflows app-ci.yaml.
# ==============================================================================
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

readonly IMAGE_SHELLCHECK="koalaman/shellcheck:v0.11.0"
readonly IMAGE_HADOLINT="hadolint/hadolint:v2.15.1-alpine"
readonly IMAGE_YAMLLINT="pipelinecomponents/yamllint:0.34.0"
readonly IMAGE_NODE="node:24-alpine"

require::docker
cd "${REPO_ROOT}"

log::step "Shellcheck"
mapfile -t scripts < <(
    find healthchecks/rootfs tests -type f \
        \( -name "*.sh" -o -path "*/s6-rc.d/*/run" -o -path "*/s6-rc.d/*/finish" \) \
        | sort
)
log::info "${#scripts[@]} scripts"
if docker run --rm -v "${PWD}:/mnt" -w /mnt -e SHELLCHECK_OPTS="-s bash" \
    "${IMAGE_SHELLCHECK}" "${scripts[@]}"; then
    assert::ok "shellcheck"
else
    assert::fail "shellcheck"
fi

log::step "Hadolint"
if docker run --rm -i "${IMAGE_HADOLINT}" hadolint - < healthchecks/Dockerfile; then
    assert::ok "hadolint"
else
    assert::fail "hadolint"
fi

log::step "YAMLLint"
if docker run --rm -v "${PWD}:/code" "${IMAGE_YAMLLINT}" yamllint .; then
    assert::ok "yamllint"
else
    assert::fail "yamllint"
fi

log::step "JSON"
json_ok=true
while read -r file; do
    if ! jq -e '.' "${file}" > /dev/null 2>&1; then
        log::info "invalid JSON: ${file}"
        json_ok=false
    fi
done < <(find . -name "*.json" -not -path "./.git/*")
if [[ "${json_ok}" == true ]]; then
    assert::ok "json parses"
else
    assert::fail "json parses"
fi

log::step "Prettier"
if docker run --rm -v "${PWD}:/work" -w /work "${IMAGE_NODE}" \
    npx --yes prettier@3 --check "**/*.{json,js,md,yaml}"; then
    assert::ok "prettier"
else
    assert::fail "prettier" "run: npx prettier@3 --write '**/*.{json,js,md,yaml}'"
fi

log::step "Python syntax"
if python3 -m py_compile \
    healthchecks/rootfs/opt/healthchecks/hc/local_settings.py \
    tests/mock-supervisor.py; then
    assert::ok "python files compile"
else
    assert::fail "python files compile"
fi

assert::summary
