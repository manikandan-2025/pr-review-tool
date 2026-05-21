#!/usr/bin/env bash
# =============================================================================
#  tests/framework.sh — Lightweight bash test framework (no external deps)
# =============================================================================

PASS=0; FAIL=0; SKIP=0
_FW_GREEN='\033[0;32m'; _FW_RED='\033[0;31m'; _FW_YELLOW='\033[1;33m'; _FW_RESET='\033[0m'

run_test() {
    local name="$1"; shift
    if "$@" 2>/tmp/fw_test_stderr; then
        printf "  ${_FW_GREEN}✔${_FW_RESET}  %s\n" "$name"; (( PASS++ )) || true
    else
        printf "  ${_FW_RED}✖${_FW_RESET}  %s\n" "$name"
        [[ -s /tmp/fw_test_stderr ]] && sed 's/^/      /' /tmp/fw_test_stderr
        (( FAIL++ )) || true
    fi
    rm -f /tmp/fw_test_stderr
}

skip_test() { printf "  ${_FW_YELLOW}◌${_FW_RESET}  %s ${_FW_YELLOW}(skipped)${_FW_RESET}\n" "$1"; (( SKIP++ )) || true; }

section() { echo ""; printf "${_FW_YELLOW}▶ %s${_FW_RESET}\n" "$*"; printf "${_FW_YELLOW}%s${_FW_RESET}\n" "──────────────────────────────────────────────────"; }

assert_eq()        { [[ "$1" == "$2" ]] || { echo "  expected: '$2'  got: '$1'" >&2; return 1; }; }
assert_ne()        { [[ "$1" != "$2" ]] || { echo "  values equal but expected different: '$1'" >&2; return 1; }; }
assert_contains()  { echo "$1" | grep -qF "$2" || { echo "  '$2' not found in: $1" >&2; return 1; }; }
assert_not_contains() { echo "$1" | grep -qF "$2" && { echo "  '$2' unexpectedly found in: $1" >&2; return 1; } || true; }
assert_match()     { echo "$1" | grep -qE "$2" || { echo "  pattern '$2' not matched in: $1" >&2; return 1; }; }
assert_file_exists()  { [[ -f "$1" ]] || { echo "  file not found: $1" >&2; return 1; }; }
assert_dir_exists()   { [[ -d "$1" ]] || { echo "  dir not found: $1" >&2; return 1; }; }
assert_file_perms()   {
    local p; p=$(stat -c "%a" "$1" 2>/dev/null || stat -f "%Lp" "$1" 2>/dev/null)
    [[ "$p" == "$2" ]] || { echo "  perms: expected $2 got $p for $1" >&2; return 1; }
}
assert_exit_zero()    { [[ $? -eq 0 ]]  || { echo "  expected exit 0" >&2; return 1; }; }
assert_exit_nonzero() { [[ $? -ne 0 ]]  || { echo "  expected non-zero exit" >&2; return 1; }; }

test_summary() {
    local total=$(( PASS + FAIL ))
    echo ""; echo "══════════════════════════════════════════════════════════"
    printf "  ${_FW_GREEN}%d passed${_FW_RESET}  ${_FW_RED}%d failed${_FW_RESET}  %d skipped  / %d total\n" \
        "$PASS" "$FAIL" "$SKIP" "$total"
    echo "══════════════════════════════════════════════════════════"
    [[ $FAIL -eq 0 ]]
}
