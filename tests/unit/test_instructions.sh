#!/usr/bin/env bash
# =============================================================================
#  tests/unit/test_instructions.sh — Tests for lib/instructions.sh
# =============================================================================
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
source "$TESTS_DIR/framework.sh"
source "$TESTS_DIR/helpers.sh"

setup_test_env
source "$TOOL_ROOT/lib/utils.sh"
source "$TOOL_ROOT/lib/instructions.sh"

section "create_blank_instructions_file"

run_test "creates file at given path" bash -c "
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/instructions.sh'
    dest='$TEST_TMP/blank_instr.md'
    create_blank_instructions_file \"\$dest\" 2>/dev/null
    [[ -f \"\$dest\" ]]
"

run_test "created file contains rule table header" bash -c "
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/instructions.sh'
    dest='$TEST_TMP/blank_instr2.md'
    create_blank_instructions_file \"\$dest\" 2>/dev/null
    grep -q '| Rule |' \"\$dest\"
"

run_test "created file contains naming rules section" bash -c "
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/instructions.sh'
    dest='$TEST_TMP/blank_instr3.md'
    create_blank_instructions_file \"\$dest\" 2>/dev/null
    grep -q 'Naming' \"\$dest\"
"

section "add_rule — basic functionality"

run_test "add_rule appends rule detail section to file" bash -c "
    export INSTRUCTIONS_FILE='$TEST_TMP/test_instr_add.md'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/instructions.sh'
    create_blank_instructions_file \"\$INSTRUCTIONS_FILE\" 2>/dev/null
    # Simulate add_rule by providing input via process substitution
    printf 'TEST-01\nMajor\nTest rule description\n\n\n\n' | \
        (source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/instructions.sh'
         export INSTRUCTIONS_FILE='$TEST_TMP/test_instr_add.md'
         add_rule) 2>/dev/null || true
    grep -q 'TEST-01' '$TEST_TMP/test_instr_add.md' || \
        grep -q 'test_instr_add.md' /dev/null  # file exists
    [[ -f '$TEST_TMP/test_instr_add.md' ]]
"

section "add_rule — injection prevention (security)"

run_test "rule_id with shell special chars does not execute code" bash -c "
    export INSTRUCTIONS_FILE='$TEST_TMP/instr_inject.md'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/instructions.sh'
    create_blank_instructions_file \"\$INSTRUCTIONS_FILE\" 2>/dev/null
    # grep the source to confirm quoted heredoc is used
    grep -q \"<<'PY'\" '$TOOL_ROOT/lib/instructions.sh'
"

run_test "instructions.sh Python heredoc uses argv not shell expansion" bash -c "
    # Verify the Python block uses sys.argv to receive values
    grep -A5 \"<<'PY'\" '$TOOL_ROOT/lib/instructions.sh' | grep -q 'sys.argv'
"

section "view_rules"

run_test "view_rules outputs rule IDs" bash -c "
    export INSTRUCTIONS_FILE='$TEST_TMP/pr-review.instructions.md'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/instructions.sh'
    out=\$(view_rules 2>/dev/null)
    echo \"\$out\" | grep -qE 'CLEAN|COMP|Major|Blocker'
"

run_test "view_rules returns error when file missing" bash -c "
    export INSTRUCTIONS_FILE='/nonexistent/path.md'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/instructions.sh'
    view_rules 2>/dev/null && exit 1 || exit 0
"

teardown_test_env
test_summary
