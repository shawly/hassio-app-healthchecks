#!/usr/bin/env bash
# ==============================================================================
# Home Assistant App: Healthchecks
#
# Runs the full local test suite: the linters CI runs, then an end-to-end boot
# of the built image against a mock Supervisor API.
#
# Usage: tests/run.sh [--lint-only|--e2e-only] [--keep] [--skip-build]
# ==============================================================================
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

run_lint=true
run_e2e=true
e2e_args=()

for arg in "$@"; do
    case "${arg}" in
        --lint-only) run_e2e=false ;;
        --e2e-only) run_lint=false ;;
        --keep | --skip-build) e2e_args+=("${arg}") ;;
        -h | --help)
            sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "unknown argument: ${arg}" >&2
            exit 1
            ;;
    esac
done

status=0
if [[ "${run_lint}" == true ]]; then
    "${here}/lint.sh" || status=1
fi
if [[ "${run_e2e}" == true ]]; then
    "${here}/e2e.sh" "${e2e_args[@]+"${e2e_args[@]}"}" || status=1
fi
exit "${status}"
