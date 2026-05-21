#!/usr/bin/env bash
# =============================================================================
#  tests/unit/test_report.sh — Tests for lib/report.sh
# =============================================================================
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
source "$TESTS_DIR/framework.sh"
source "$TESTS_DIR/helpers.sh"

setup_test_env
source "$TOOL_ROOT/lib/utils.sh"
source "$TOOL_ROOT/lib/analyze.sh"
source "$TOOL_ROOT/lib/report.sh"

section "get_report_path"

run_test "returns path inside REPORTS_DIR" bash -c "
    export REPORTS_DIR='$TEST_TMP/reports'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/report.sh'
    out=\$(get_report_path 42)
    echo \"\$out\" | grep -q '$TEST_TMP/reports'
"

run_test "includes PR number in filename" bash -c "
    export REPORTS_DIR='$TEST_TMP/reports'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/report.sh'
    out=\$(get_report_path 42)
    echo \"\$out\" | grep -q 'pr-42'
"

run_test "filename ends with .md" bash -c "
    export REPORTS_DIR='$TEST_TMP/reports'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/report.sh'
    out=\$(get_report_path 42)
    [[ \"\$out\" == *.md ]]
"

section "generate_report — file creation and content"

run_test "creates report file" bash -c "
    export PATH='$TEST_BIN:$PATH'
    export REPORTS_DIR='$TEST_TMP/reports'
    export GITHUB_REPO='testorg/testrepo'
    export INSTRUCTIONS_FILE='$TEST_TMP/pr-review.instructions.md'
    install -d -m 700 '$TEST_TMP/reports'
    declare -a FINDINGS=(); COUNT_BLOCKER=0; COUNT_MAJOR=0; COUNT_MINOR=0
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/analyze.sh'; source '$TOOL_ROOT/lib/report.sh'
    path=\$(generate_report 42 'My Test PR' 'alice' 'main' '2024-01-01' 'abc123' '> AI analysis skipped.' '' 2>/dev/null)
    [[ -f \"\$path\" ]]
"

run_test "report file has 600 permissions" bash -c "
    export PATH='$TEST_BIN:$PATH'
    export REPORTS_DIR='$TEST_TMP/reports2'
    export GITHUB_REPO='testorg/testrepo'
    export INSTRUCTIONS_FILE='$TEST_TMP/pr-review.instructions.md'
    install -d -m 700 '$TEST_TMP/reports2'
    declare -a FINDINGS=(); COUNT_BLOCKER=0; COUNT_MAJOR=0; COUNT_MINOR=0
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/analyze.sh'; source '$TOOL_ROOT/lib/report.sh'
    path=\$(generate_report 99 'Perm Test PR' 'bob' 'main' '2024-01-01' 'abc123' '> skip' '' 2>/dev/null)
    p=\$(stat -c '%a' \"\$path\" 2>/dev/null || stat -f '%Lp' \"\$path\")
    [[ \"\$p\" == '600' ]]
"

run_test "report contains PR number" bash -c "
    export PATH='$TEST_BIN:$PATH'
    export REPORTS_DIR='$TEST_TMP/reports3'
    export GITHUB_REPO='testorg/testrepo'
    export INSTRUCTIONS_FILE='$TEST_TMP/pr-review.instructions.md'
    install -d -m 700 '$TEST_TMP/reports3'
    declare -a FINDINGS=(); COUNT_BLOCKER=0; COUNT_MAJOR=0; COUNT_MINOR=0
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/analyze.sh'; source '$TOOL_ROOT/lib/report.sh'
    path=\$(generate_report 77 'Title' 'alice' 'main' '2024-01-01' 'abc123' '' '' 2>/dev/null)
    grep -q '#77' \"\$path\"
"

run_test "report contains author name" bash -c "
    export PATH='$TEST_BIN:$PATH'
    export REPORTS_DIR='$TEST_TMP/reports4'
    export GITHUB_REPO='testorg/testrepo'
    export INSTRUCTIONS_FILE='$TEST_TMP/pr-review.instructions.md'
    install -d -m 700 '$TEST_TMP/reports4'
    declare -a FINDINGS=(); COUNT_BLOCKER=0; COUNT_MAJOR=0; COUNT_MINOR=0
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/analyze.sh'; source '$TOOL_ROOT/lib/report.sh'
    path=\$(generate_report 1 'Title' 'superdev' 'main' '2024-01-01' 'abc123' '' '' 2>/dev/null)
    grep -q 'superdev' \"\$path\"
"

run_test "report shows APPROVED when no findings" bash -c "
    export PATH='$TEST_BIN:$PATH'
    export REPORTS_DIR='$TEST_TMP/reports5'
    export GITHUB_REPO='testorg/testrepo'
    export INSTRUCTIONS_FILE='$TEST_TMP/pr-review.instructions.md'
    install -d -m 700 '$TEST_TMP/reports5'
    declare -a FINDINGS=(); COUNT_BLOCKER=0; COUNT_MAJOR=0; COUNT_MINOR=0
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/analyze.sh'; source '$TOOL_ROOT/lib/report.sh'
    path=\$(generate_report 1 'Clean PR' 'dev' 'main' '2024-01-01' 'abc123' '' '' 2>/dev/null)
    grep -q 'APPROVED' \"\$path\"
"

section "get_rule_description + get_rule_fix"

run_test "get_rule_description returns known rule CLEAN-04" bash -c "
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/report.sh'
    desc=\$(get_rule_description 'CLEAN-04')
    echo \"\$desc\" | grep -qi 'console'
"

run_test "get_rule_description returns known rule COMP-06" bash -c "
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/report.sh'
    desc=\$(get_rule_description 'COMP-06')
    echo \"\$desc\" | grep -qi 'subscribe\|OnDestroy'
"

run_test "get_rule_fix returns fix for CLEAN-04" bash -c "
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/report.sh'
    fix=\$(get_rule_fix 'CLEAN-04')
    echo \"\$fix\" | grep -qi 'remove\|console'
"

teardown_test_env
test_summary
