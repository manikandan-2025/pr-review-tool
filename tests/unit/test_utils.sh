#!/usr/bin/env bash
# =============================================================================
#  tests/unit/test_utils.sh — Tests for lib/utils.sh
# =============================================================================
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
source "$TESTS_DIR/framework.sh"
source "$TESTS_DIR/helpers.sh"

setup_test_env
source "$TOOL_ROOT/lib/utils.sh"

section "ensure_dirs — creates dirs with mode 700"

run_test "creates REPORTS_DIR" bash -c "
    source '$TOOL_ROOT/lib/utils.sh'
    REPORTS_DIR='$TEST_TMP/rpt_test'
    CHECKOUTS_DIR='$TEST_TMP/chk_test'
    ensure_dirs
    [[ -d '$TEST_TMP/rpt_test' ]]
"

run_test "creates CHECKOUTS_DIR" bash -c "
    source '$TOOL_ROOT/lib/utils.sh'
    REPORTS_DIR='$TEST_TMP/rpt2'
    CHECKOUTS_DIR='$TEST_TMP/chk2'
    ensure_dirs
    [[ -d '$TEST_TMP/chk2' ]]
"

run_test "REPORTS_DIR has mode 700" bash -c "
    source '$TOOL_ROOT/lib/utils.sh'
    REPORTS_DIR='$TEST_TMP/rpt700'
    CHECKOUTS_DIR='$TEST_TMP/chk700'
    ensure_dirs
    p=\$(stat -c '%a' '$TEST_TMP/rpt700' 2>/dev/null || stat -f '%Lp' '$TEST_TMP/rpt700')
    [[ \"\$p\" == '700' ]]
"

run_test "CHECKOUTS_DIR has mode 700" bash -c "
    source '$TOOL_ROOT/lib/utils.sh'
    REPORTS_DIR='$TEST_TMP/rpt700b'
    CHECKOUTS_DIR='$TEST_TMP/chk700b'
    ensure_dirs
    p=\$(stat -c '%a' '$TEST_TMP/chk700b' 2>/dev/null || stat -f '%Lp' '$TEST_TMP/chk700b')
    [[ \"\$p\" == '700' ]]
"

section "require_command"

run_test "require_command passes for existing command (true)" bash -c "
    source '$TOOL_ROOT/lib/utils.sh'
    require_command true
"

run_test "require_command exits for missing command" bash -c "
    source '$TOOL_ROOT/lib/utils.sh'
    require_command _nonexistent_cmd_xyz_ 2>/dev/null && exit 1 || exit 0
"

section "severity helpers"

run_test "severity_emoji BLOCKER returns red circle" bash -c "
    source '$TOOL_ROOT/lib/utils.sh'
    result=\$(severity_emoji 'BLOCKER')
    [[ \"\$result\" == '🔴' ]]
"

run_test "severity_emoji MAJOR returns orange circle" bash -c "
    source '$TOOL_ROOT/lib/utils.sh'
    result=\$(severity_emoji 'MAJOR')
    [[ \"\$result\" == '🟠' ]]
"

run_test "severity_emoji MINOR returns yellow circle" bash -c "
    source '$TOOL_ROOT/lib/utils.sh'
    result=\$(severity_emoji 'MINOR')
    [[ \"\$result\" == '🟡' ]]
"

teardown_test_env
test_summary
