#!/usr/bin/env bash
# ==============================================================================
# Shared helpers for the app test scripts.
# ==============================================================================

# Consumed by the scripts that source this file.
# shellcheck disable=SC2034
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly REPO_ROOT

TESTS_RUN=0
TESTS_FAILED=0

readonly C_RESET=$'\033[0m'
readonly C_RED=$'\033[31m'
readonly C_GREEN=$'\033[32m'
readonly C_BLUE=$'\033[34m'

log::step() { printf '\n%s==> %s%s\n' "${C_BLUE}" "${1}" "${C_RESET}"; }
log::info() { printf '    %s\n' "${1}"; }

# Records a passing or failing assertion. Never aborts: one broken assertion
# should not hide the state of the others.
assert::ok() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf '  %sPASS%s %s\n' "${C_GREEN}" "${C_RESET}" "${1}"
}

assert::fail() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf '  %sFAIL%s %s\n' "${C_RED}" "${C_RESET}" "${1}"
    if [[ -n "${2:-}" ]]; then
        printf '       %s\n' "${2}"
    fi
}

assert::equals() {
    local desc="${1}" expected="${2}" actual="${3}"
    if [[ "${expected}" == "${actual}" ]]; then
        assert::ok "${desc}"
    else
        assert::fail "${desc}" "expected '${expected}', got '${actual}'"
    fi
}

assert::contains() {
    local desc="${1}" haystack="${2}" needle="${3}"
    if [[ "${haystack}" == *"${needle}"* ]]; then
        assert::ok "${desc}"
    else
        assert::fail "${desc}" "'${needle}' not found"
    fi
}

assert::not_contains() {
    local desc="${1}" haystack="${2}" needle="${3}"
    if [[ "${haystack}" != *"${needle}"* ]]; then
        assert::ok "${desc}"
    else
        assert::fail "${desc}" "'${needle}' should not be present"
    fi
}

assert::summary() {
    printf '\n'
    if [[ "${TESTS_FAILED}" -eq 0 ]]; then
        printf '%s%d/%d checks passed%s\n' \
            "${C_GREEN}" "${TESTS_RUN}" "${TESTS_RUN}" "${C_RESET}"
        return 0
    fi
    printf '%s%d of %d checks failed%s\n' \
        "${C_RED}" "${TESTS_FAILED}" "${TESTS_RUN}" "${C_RESET}"
    return 1
}

bail() {
    printf '%sERROR:%s %s\n' "${C_RED}" "${C_RESET}" "${1}" >&2
    exit 1
}

require::docker() {
    command -v docker > /dev/null 2>&1 \
        || bail "docker is required to run these tests"
    docker info > /dev/null 2>&1 \
        || bail "the docker daemon is not reachable"
}
