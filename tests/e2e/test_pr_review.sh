#!/usr/bin/env bash
# =============================================================================
#  tests/e2e/test_pr_review.sh — E2E tests for full PR review workflow
# =============================================================================
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
source "$TESTS_DIR/framework.sh"
source "$TESTS_DIR/helpers.sh"

setup_test_env

section "Full PR review workflow — mocked gh + git"

run_test "fetch_pr_metadata returns expected PR fields" bash -c "
    export PATH='$TEST_BIN:$PATH'
    export TOOL_DIR='$TEST_TMP'
    export GITHUB_REPO='testorg/testrepo'
    export MOCK_PR_META='{\"title\":\"E2E Test PR\",\"author\":\"e2euser\",\"base\":\"main\",\"state\":\"open\",\"created_at\":\"2024-06-01T10:00:00Z\",\"body\":\"E2E body\"}'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/checkout.sh'
    meta=\$(fetch_pr_metadata 100 2>/dev/null)
    echo \"\$meta\" | python3 -c \"import sys,json; d=json.load(sys.stdin); assert d['title']=='E2E Test PR'\"
"

run_test "fetch_pr succeeds with mock git" bash -c "
    export PATH='$TEST_BIN:$PATH'
    export MOCK_GIT_FETCH_EXIT=0
    export REPO_PATH='$TEST_TMP/mock_repo'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/checkout.sh'
    start_spinner() { :; }; stop_spinner() { :; }
    fetch_pr 100 2>/dev/null
"

run_test "create_worktree creates directory" bash -c "
    export PATH='$TEST_BIN:$PATH'
    export MOCK_GIT_WT_ADD_EXIT=0
    export REPO_PATH='$TEST_TMP/mock_repo'
    export CHECKOUTS_DIR='$TEST_TMP/checkouts'
    mkdir -p '$TEST_TMP/checkouts'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/checkout.sh'
    start_spinner() { :; }; stop_spinner() { :; }
    out=\$(create_worktree 100 2>/dev/null)
    [[ -d \"\$out\" ]]
"

run_test "find_merge_base returns SHA from mock gh api" bash -c "
    export PATH='$TEST_BIN:$PATH'
    export TOOL_DIR='$TEST_TMP'
    export GITHUB_REPO='testorg/testrepo'
    export REPO_PATH='$TEST_TMP/mock_repo'
    export MOCK_PR_META='{\"base\":{\"sha\":\"deadbeef1234\"}}'
    # Override mock to return .base.sha
    cat > '$TEST_BIN/gh' << 'GEOF'
#!/usr/bin/env bash
echo 'deadbeef1234'
exit 0
GEOF
    chmod +x '$TEST_BIN/gh'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/checkout.sh'
    base=\$(find_merge_base 100 'main' 2>/dev/null)
    [[ \"\$base\" == 'deadbeef1234' ]]
"

run_test "generate_report creates file with correct verdict for 0 findings" bash -c "
    export PATH='$TEST_BIN:$PATH'
    export REPORTS_DIR='$TEST_TMP/e2e_reports'
    export GITHUB_REPO='testorg/testrepo'
    export INSTRUCTIONS_FILE='$TEST_TMP/pr-review.instructions.md'
    install -d -m 700 '$TEST_TMP/e2e_reports'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/analyze.sh'; source '$TOOL_ROOT/lib/report.sh'
    declare -a FINDINGS=(); COUNT_BLOCKER=0; COUNT_MAJOR=0; COUNT_MINOR=0
    path=\$(generate_report 100 'E2E PR' 'e2euser' 'main' '2024-06-01' 'abc123' '> skip' '' 2>/dev/null)
    grep -q 'APPROVED' \"\$path\"
    grep -q 'E2E PR' \"\$path\"
    grep -q 'e2euser' \"\$path\"
"

run_test "full scan pipeline detects console.log and reflects in report" bash -c "
    export PATH='$TEST_BIN:$PATH'
    export REPORTS_DIR='$TEST_TMP/e2e_reports2'
    export GITHUB_REPO='testorg/testrepo'
    export INSTRUCTIONS_FILE='$TEST_TMP/pr-review.instructions.md'
    export CHECKOUTS_DIR='$TEST_TMP/checkouts2'
    install -d -m 700 '$TEST_TMP/e2e_reports2' '$TEST_TMP/checkouts2'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/analyze.sh'; source '$TOOL_ROOT/lib/report.sh'

    declare -a FINDINGS=(); COUNT_BLOCKER=0; COUNT_MAJOR=0; COUNT_MINOR=0
    WORKTREE='$TEST_TMP/checkouts2/pr-55'
    mkdir -p \"\$WORKTREE/src\"
    echo 'console.log(\"debug\");' > \"\$WORKTREE/src/app.ts\"
    echo 'console.log(\"more\");' >> \"\$WORKTREE/src/app.ts\"

    scan_console_log \"\$WORKTREE\" 'src/app.ts'
    path=\$(generate_report 55 'Dirty PR' 'dev' 'main' '2024-06-01' 'abc123' '' '' 2>/dev/null)
    grep -q 'NEEDS CHANGES\|BLOCKED' \"\$path\"
    [[ \$COUNT_MAJOR -ge 2 ]]
"

section "save_manual_prompt — file permissions"

run_test "manual prompt file created with 600 permissions" bash -c "
    export REPORTS_DIR='$TEST_TMP/e2e_reports3'
    export TOOL_DIR='$TEST_TMP'
    install -d -m 700 '$TEST_TMP/e2e_reports3'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/analyze.sh'
    source '$TOOL_ROOT/lib/copilot.sh'
    report_path='$TEST_TMP/e2e_reports3/pr-66-review-2024-01-01.md'
    save_manual_prompt 'Test prompt content' \"\$report_path\" 2>/dev/null
    prompt_file=\"\${report_path%.md}-copilot-prompt.md\"
    p=\$(stat -c '%a' \"\$prompt_file\" 2>/dev/null || stat -f '%Lp' \"\$prompt_file\")
    [[ \"\$p\" == '600' ]]
"

teardown_test_env
test_summary
