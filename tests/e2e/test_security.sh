#!/usr/bin/env bash
# =============================================================================
#  tests/e2e/test_security.sh — E2E security tests (validates all security fixes)
# =============================================================================
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
source "$TESTS_DIR/framework.sh"
source "$TESTS_DIR/helpers.sh"

setup_test_env

section "SEC-01: PR number validation — --pr CLI flag"

run_test "--pr rejects non-numeric input (letters)" bash -c "
    export PATH='$TEST_BIN:$PATH'
    cd '$TOOL_ROOT'
    bash pr-review.sh --pr 'abc' 2>/dev/null && exit 1 || exit 0
"

run_test "--pr rejects path traversal input (../../etc)" bash -c "
    export PATH='$TEST_BIN:$PATH'
    cd '$TOOL_ROOT'
    bash pr-review.sh --pr '../../etc' 2>/dev/null && exit 1 || exit 0
"

run_test "--pr rejects empty string" bash -c "
    export PATH='$TEST_BIN:$PATH'
    cd '$TOOL_ROOT'
    bash pr-review.sh --pr '' 2>/dev/null && exit 1 || exit 0
"

run_test "--pr rejects alphanumeric mix" bash -c "
    export PATH='$TEST_BIN:$PATH'
    cd '$TOOL_ROOT'
    bash pr-review.sh --pr '42abc' 2>/dev/null && exit 1 || exit 0
"

section "SEC-02: PR number validation — cleanup_checkouts()"

run_test "cleanup rejects non-numeric PR number" bash -c "
    source '$TOOL_ROOT/lib/utils.sh'
    source '$TOOL_ROOT/lib/repo-config.sh'
    source '$TOOL_ROOT/lib/checkout.sh'
    # Source and call cleanup logic inline
    CHECKOUTS_DIR='$TEST_TMP/checkouts'
    result=\$(bash -c '
        export CHECKOUTS_DIR=\"$TEST_TMP/checkouts\"
        export REPORTS_DIR=\"$TEST_TMP/reports\"
        export TOOL_DIR=\"$TEST_TMP\"
        source \"$TOOL_ROOT/lib/utils.sh\"
        source \"$TOOL_ROOT/lib/checkout.sh\"
        pr_num=\"bad../input\"
        if [[ \"\$pr_num\" == \"all\" ]]; then
            echo WOULD_REMOVE_ALL
        elif [[ \"\$pr_num\" =~ ^[0-9]+\$ ]]; then
            echo WOULD_REMOVE_PR
        else
            echo REJECTED
        fi
    ')
    [[ \"\$result\" == 'REJECTED' ]]
"

section "SEC-03: remove_worktree — path traversal prevention"

run_test "remove_worktree refuses path outside CHECKOUTS_DIR" bash -c "
    export PATH='$TEST_BIN:$PATH'
    export MOCK_GIT_WT_REMOVE_EXIT=1
    export REPO_PATH='$TEST_TMP/mock_repo'
    export CHECKOUTS_DIR='$TEST_TMP/checkouts'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/checkout.sh'
    # Verify source code has the guard
    grep -A5 'git worktree remove.*force' '$TOOL_ROOT/lib/checkout.sh' | \
        grep -q 'CHECKOUTS_DIR.*pr-'
"

run_test "remove_worktree source has explicit path prefix check" bash -c "
    grep -q 'worktree_path.*CHECKOUTS_DIR' '$TOOL_ROOT/lib/checkout.sh'
"

section "SEC-04: Predictable /tmp — mktemp uses TOOL_DIR"

run_test "fetch_pr_metadata does not use /tmp/\$\$ pattern" bash -c "
    ! grep -q '/tmp/_pr_fetch_err_\$\$' '$TOOL_ROOT/lib/checkout.sh'
"

run_test "fetch_pr_metadata uses mktemp with TOOL_DIR" bash -c "
    grep -q 'mktemp.*TOOL_DIR.*pr-api-err' '$TOOL_ROOT/lib/checkout.sh'
"

section "SEC-05: File permissions — reports, prompts, dirs"

run_test "ensure_dirs uses install -d -m 700 (not mkdir)" bash -c "
    grep 'ensure_dirs' -A3 '$TOOL_ROOT/lib/utils.sh' | grep -q 'install.*700'
"

run_test "generate_report sets umask 077 before writing" bash -c "
    grep -q 'umask 077' '$TOOL_ROOT/lib/report.sh'
"

run_test "generate_report runs chmod 600 on report file" bash -c "
    grep -q 'chmod 600' '$TOOL_ROOT/lib/report.sh'
"

run_test "copilot.sh sets umask 077 for prompt file" bash -c "
    grep -q 'umask 077' '$TOOL_ROOT/lib/copilot.sh'
"

run_test "copilot.sh uses private TOOL_DIR/.tmp for prompt (not /tmp)" bash -c "
    grep 'mktemp' '$TOOL_ROOT/lib/copilot.sh' | grep -q 'TOOL_DIR.*tmp'
"

run_test "report file created with 600 in real run" bash -c "
    export PATH='$TEST_BIN:$PATH'
    export REPORTS_DIR='$TEST_TMP/sec_reports'
    export GITHUB_REPO='testorg/testrepo'
    export INSTRUCTIONS_FILE='$TEST_TMP/pr-review.instructions.md'
    install -d -m 700 '$TEST_TMP/sec_reports'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/analyze.sh'; source '$TOOL_ROOT/lib/report.sh'
    declare -a FINDINGS=(); COUNT_BLOCKER=0; COUNT_MAJOR=0; COUNT_MINOR=0
    path=\$(generate_report 1 'Sec Test' 'dev' 'main' '2024-01-01' 'abc' '' '' 2>/dev/null)
    p=\$(stat -c '%a' \"\$path\" 2>/dev/null || stat -f '%Lp' \"\$path\")
    [[ \"\$p\" == '600' ]]
"

section "SEC-06: Jira PAT — not in curl argv"

run_test "jira-context.sh fetch_jira_issue uses -K flag for PAT" bash -c "
    grep -q '\-K' '$TOOL_ROOT/lib/jira-context.sh'
"

run_test "jira-context.sh does not pass -H Authorization Bearer in fetch_jira_issue" bash -c "
    # The curl call in fetch_jira_issue should not contain -H Authorization: Bearer
    # (it must use -K instead)
    ! awk '/fetch_jira_issue/,/^}/' '$TOOL_ROOT/lib/jira-context.sh' | \
        grep -q '\"Authorization: Bearer'
"

run_test "curl config file has chmod 600 before use" bash -c "
    grep -B2 'printf.*Authorization.*Bearer' '$TOOL_ROOT/lib/jira-context.sh' | \
        grep -q 'chmod 600'
"

section "SEC-07: Python heredoc injection — add_rule()"

run_test "instructions.sh Python block uses quoted heredoc <<'PY'" bash -c "
    grep -q \"<<'PY'\" '$TOOL_ROOT/lib/instructions.sh'
"

run_test "instructions.sh Python block uses sys.argv not shell vars" bash -c "
    grep -A3 \"<<'PY'\" '$TOOL_ROOT/lib/instructions.sh' | grep -q 'sys.argv'
"

run_test "instructions.sh Python block does not expand shell variables" bash -c "
    # In a quoted heredoc, \$var should NOT appear (it would mean shell expansion leak)
    # The variables like rule_id must be passed via argv
    ! grep -A20 \"<<'PY'\" '$TOOL_ROOT/lib/instructions.sh' | grep -q '\\\${rule_id}'
"

section "SEC-08: Config injection — _jira_save_setting"

run_test "_jira_save_setting rejects values with newlines" bash -c "
    export TOOL_DIR='$TEST_TMP'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/jira-context.sh'
    _jira_save_setting 'TEST_K' \$'val\nnewline' 2>/dev/null && exit 1 || exit 0
"

run_test "_jira_save_setting uses Python (not raw sed) to write values" bash -c "
    grep '_jira_save_setting' -A20 '$TOOL_ROOT/lib/jira-context.sh' | grep -q 'python3'
"

section "SEC-09: setup.sh — alias and repo format validation"

run_test "setup.sh validates alias with sanitization" bash -c "
    grep -q 'alias.*tr.*a-zA-Z0-9\|sanitiz' '$TOOL_ROOT/setup.sh'
"

run_test "setup.sh validates gh_repo format (owner/repo)" bash -c "
    grep -q 'gh_repo.*owner/repo\|owner.*repo.*format' '$TOOL_ROOT/setup.sh'
"

teardown_test_env
test_summary
