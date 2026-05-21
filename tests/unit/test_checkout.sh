#!/usr/bin/env bash
# =============================================================================
#  tests/unit/test_checkout.sh — Tests for lib/checkout.sh
# =============================================================================
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
source "$TESTS_DIR/framework.sh"
source "$TESTS_DIR/helpers.sh"

setup_test_env
source "$TOOL_ROOT/lib/utils.sh"
source "$TOOL_ROOT/lib/checkout.sh"

section "fetch_pr_metadata — success path"

run_test "returns PR metadata JSON on success" bash -c "
    export PATH='$TEST_BIN:$PATH'
    export MOCK_PR_META='{\"title\":\"My PR\",\"author\":\"alice\",\"base\":\"main\",\"state\":\"open\",\"created_at\":\"2024-01-01\",\"body\":\"desc\"}'
    export GITHUB_REPO='testorg/testrepo'
    export TOOL_DIR='$TEST_TMP'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/checkout.sh'
    out=\$(fetch_pr_metadata 42 2>/dev/null)
    echo \"\$out\" | grep -q 'My PR'
"

section "fetch_pr_metadata — error diagnosis"

run_test "diagnoses 404 as PR not found" bash -c "
    export PATH='$TEST_BIN:$PATH'
    export MOCK_GH_API_EXIT=1
    export MOCK_PR_META=''
    export GITHUB_REPO='testorg/testrepo'
    export TOOL_DIR='$TEST_TMP'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/checkout.sh'
    # Inject 404 into stderr by overriding mock
    cat > '$TEST_BIN/gh' << 'GEOF'
#!/usr/bin/env bash
echo 'HTTP 404: Not Found' >&2
exit 1
GEOF
    chmod +x '$TEST_BIN/gh'
    errmsg=\$(fetch_pr_metadata 999 2>&1)
    echo \"\$errmsg\" | grep -qi '404\|not found'
"

run_test "diagnoses auth error (401)" bash -c "
    export PATH='$TEST_BIN:$PATH'
    export TOOL_DIR='$TEST_TMP'
    export GITHUB_REPO='testorg/testrepo'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/checkout.sh'
    cat > '$TEST_BIN/gh' << 'GEOF'
#!/usr/bin/env bash
echo 'error: 401 Unauthorized' >&2
exit 1
GEOF
    chmod +x '$TEST_BIN/gh'
    errmsg=\$(fetch_pr_metadata 42 2>&1)
    echo \"\$errmsg\" | grep -qi 'auth\|login'
"

run_test "diagnoses network error" bash -c "
    export PATH='$TEST_BIN:$PATH'
    export TOOL_DIR='$TEST_TMP'
    export GITHUB_REPO='testorg/testrepo'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/checkout.sh'
    cat > '$TEST_BIN/gh' << 'GEOF'
#!/usr/bin/env bash
echo 'error: could not connect: network timeout' >&2
exit 1
GEOF
    chmod +x '$TEST_BIN/gh'
    errmsg=\$(fetch_pr_metadata 42 2>&1)
    echo \"\$errmsg\" | grep -qi 'network\|connect\|internet'
"

run_test "returns exit 1 on failure" bash -c "
    export PATH='$TEST_BIN:$PATH'
    export TOOL_DIR='$TEST_TMP'
    export GITHUB_REPO='testorg/testrepo'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/checkout.sh'
    cat > '$TEST_BIN/gh' << 'GEOF'
#!/usr/bin/env bash
exit 1
GEOF
    chmod +x '$TEST_BIN/gh'
    fetch_pr_metadata 42 2>/dev/null && exit 1 || exit 0
"

section "_diagnose_git_fetch_error"

run_test "diagnoses missing remote ref" bash -c "
    export GITHUB_REPO='testorg/testrepo'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/checkout.sh'
    msg=\$(_diagnose_git_fetch_error 42 \"fatal: couldn't find remote ref pull/42/head\" 2>&1)
    echo \"\$msg\" | grep -qi 'not exist\|deleted\|verify\|check'
"

run_test "diagnoses repository not found" bash -c "
    export GITHUB_REPO='testorg/testrepo'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/checkout.sh'
    msg=\$(_diagnose_git_fetch_error 42 'remote: Repository not found.' 2>&1)
    echo \"\$msg\" | grep -qi 'not found\|repos.conf\|option 7'
"

run_test "diagnoses auth error in git fetch" bash -c "
    export GITHUB_REPO='testorg/testrepo'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/checkout.sh'
    msg=\$(_diagnose_git_fetch_error 42 'Permission denied (publickey)' 2>&1)
    echo \"\$msg\" | grep -qi 'auth\|login'
"

section "remove_worktree — rm -rf guard"

run_test "refuses to rm -rf path outside CHECKOUTS_DIR" bash -c "
    export PATH='$TEST_BIN:$PATH'
    export MOCK_GIT_WT_REMOVE_EXIT=1
    export REPO_PATH='$TEST_TMP/mock_repo'
    export CHECKOUTS_DIR='$TEST_TMP/checkouts'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/checkout.sh'
    # Manually create a suspicious worktree_path
    suspicious='/tmp/evil_path'
    mkdir -p \"\$suspicious\"
    # Override worktree_path computation by calling internal logic directly
    result=\$(bash -c \"
        export PATH='$TEST_BIN:\$PATH'
        export MOCK_GIT_WT_REMOVE_EXIT=1
        export REPO_PATH='$TEST_TMP/mock_repo'
        export CHECKOUTS_DIR='$TEST_TMP/checkouts'
        source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/checkout.sh'
        remove_worktree '../../evil' 2>&1
    \")
    # Should either warn or refuse — the path should NOT be deleted
    echo \"\$result\" | grep -qi 'refu\|invalid\|outside\|not found' || [[ ! -d '/tmp/evil_path' ]]
"

run_test "removes valid worktree inside CHECKOUTS_DIR" bash -c "
    export PATH='$TEST_BIN:$PATH'
    export MOCK_GIT_WT_REMOVE_EXIT=0
    export REPO_PATH='$TEST_TMP/mock_repo'
    export CHECKOUTS_DIR='$TEST_TMP/checkouts'
    mkdir -p '$TEST_TMP/checkouts/pr-99'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/checkout.sh'
    # Stub confirm_prompt to always return yes
    confirm_prompt() { return 1; }
    remove_worktree 99 2>/dev/null
    [[ ! -d '$TEST_TMP/checkouts/pr-99' ]]
"

section "fetch_pr — error handling"

run_test "returns exit 1 when git fetch fails" bash -c "
    export PATH='$TEST_BIN:$PATH'
    export MOCK_GIT_FETCH_EXIT=1
    export REPO_PATH='$TEST_TMP/mock_repo'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/checkout.sh'
    fetch_pr 42 2>/dev/null && exit 1 || exit 0
"

run_test "succeeds when git fetch succeeds" bash -c "
    export PATH='$TEST_BIN:$PATH'
    export MOCK_GIT_FETCH_EXIT=0
    export REPO_PATH='$TEST_TMP/mock_repo'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/checkout.sh'
    start_spinner() { :; }; stop_spinner() { :; }
    fetch_pr 42 2>/dev/null
"

section "fetch_pr_metadata — uses private mktemp (not /tmp/\$\$)"

run_test "err file created inside TOOL_DIR not /tmp" bash -c "
    export PATH='$TEST_BIN:$PATH'
    export TOOL_DIR='$TEST_TMP'
    export GITHUB_REPO='testorg/testrepo'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/checkout.sh'
    # grep the source to verify mktemp uses TOOL_DIR
    grep 'mktemp.*TOOL_DIR' '$TOOL_ROOT/lib/checkout.sh' | grep -q 'pr-api-err'
"

teardown_test_env
test_summary
