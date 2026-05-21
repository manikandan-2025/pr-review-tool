#!/usr/bin/env bash
# =============================================================================
#  tests/run_tests.sh — Run all tests and print combined summary
#
#  Usage:
#    cd <pr-review-tool-root>
#    bash tests/run_tests.sh
#    bash tests/run_tests.sh --unit       # unit tests only
#    bash tests/run_tests.sh --e2e        # e2e tests only
#    bash tests/run_tests.sh --security   # security tests only
# =============================================================================

set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

_G='\033[0;32m'; _R='\033[0;31m'; _Y='\033[1;33m'; _C='\033[0;36m'; _B='\033[1m'; _RS='\033[0m'

filter="${1:-}"

TOTAL_PASS=0; TOTAL_FAIL=0; TOTAL_SKIP=0
declare -a FAILED_SUITES=()

run_suite() {
    local name="$1" file="$2"
    [[ ! -f "$file" ]] && { echo "  ${_Y}⚠${_RS}  Suite not found: $file"; return; }

    printf "\n${_B}${_C}╔══════════════════════════════════════════════════════════╗${_RS}\n"
    printf "${_B}${_C}║  %-56s  ║${_RS}\n" "$name"
    printf "${_B}${_C}╚══════════════════════════════════════════════════════════╝${_RS}\n\n"

    local suite_out; suite_out=$(bash "$file" 2>&1) || true
    local pass fail skip
    pass=$(echo "$suite_out" | grep -c $'✔' 2>/dev/null || echo 0)
    fail=$(echo "$suite_out" | grep -c $'✖' 2>/dev/null || echo 0)
    skip=$(echo "$suite_out" | grep -c $'◌' 2>/dev/null || echo 0)

    echo "$suite_out" | grep -v '══════' | grep -v 'passed\|failed\|skipped'
    echo ""
    printf "  ${_G}%d passed${_RS}  ${_R}%d failed${_RS}  %d skipped\n" "$pass" "$fail" "$skip"

    TOTAL_PASS=$(( TOTAL_PASS + pass ))
    TOTAL_FAIL=$(( TOTAL_FAIL + fail ))
    TOTAL_SKIP=$(( TOTAL_SKIP + skip ))
    [[ $fail -gt 0 ]] && FAILED_SUITES+=("$name")
    return 0
}

echo ""
printf "${_B}${_C}  PR Review Tool — Test Runner${_RS}\n"
printf "${_B}${_C}  ========================================${_RS}\n"
echo ""

UNIT_SUITES=(
    "Utils (lib/utils.sh)"                    "$TESTS_DIR/unit/test_utils.sh"
    "Repo Config (lib/repo-config.sh)"        "$TESTS_DIR/unit/test_repo_config.sh"
    "Checkout (lib/checkout.sh)"              "$TESTS_DIR/unit/test_checkout.sh"
    "Report (lib/report.sh)"                  "$TESTS_DIR/unit/test_report.sh"
    "Instructions (lib/instructions.sh)"      "$TESTS_DIR/unit/test_instructions.sh"
    "Jira Context (lib/jira-context.sh)"      "$TESTS_DIR/unit/test_jira.sh"
    "Analyze (lib/analyze.sh)"                "$TESTS_DIR/unit/test_analyze.sh"
)

E2E_SUITES=(
    "E2E: PR Review Workflow"                 "$TESTS_DIR/e2e/test_pr_review.sh"
    "E2E: Security Fixes"                     "$TESTS_DIR/e2e/test_security.sh"
)

case "$filter" in
    --unit)
        for (( i=0; i<${#UNIT_SUITES[@]}; i+=2 )); do
            run_suite "${UNIT_SUITES[$i]}" "${UNIT_SUITES[$((i+1))]}"
        done ;;
    --e2e)
        for (( i=0; i<${#E2E_SUITES[@]}; i+=2 )); do
            run_suite "${E2E_SUITES[$i]}" "${E2E_SUITES[$((i+1))]}"
        done ;;
    --security)
        run_suite "E2E: Security Fixes" "$TESTS_DIR/e2e/test_security.sh" ;;
    *)
        for (( i=0; i<${#UNIT_SUITES[@]}; i+=2 )); do
            run_suite "${UNIT_SUITES[$i]}" "${UNIT_SUITES[$((i+1))]}"
        done
        for (( i=0; i<${#E2E_SUITES[@]}; i+=2 )); do
            run_suite "${E2E_SUITES[$i]}" "${E2E_SUITES[$((i+1))]}"
        done ;;
esac

TOTAL=$(( TOTAL_PASS + TOTAL_FAIL ))
echo ""
echo "══════════════════════════════════════════════════════════"
printf "  ${_B}TOTAL: ${_G}%d passed${_RS}  ${_R}%d failed${_RS}  %d skipped  / %d tests${_RS}\n" \
    "$TOTAL_PASS" "$TOTAL_FAIL" "$TOTAL_SKIP" "$TOTAL"

if [[ ${#FAILED_SUITES[@]} -gt 0 ]]; then
    echo ""
    printf "  ${_R}Failed suites:${_RS}\n"
    for s in "${FAILED_SUITES[@]}"; do printf "    ${_R}✖${_RS}  %s\n" "$s"; done
fi
echo "══════════════════════════════════════════════════════════"
echo ""
[[ $TOTAL_FAIL -eq 0 ]]
