#!/usr/bin/env bash
# =============================================================================
#  tests/unit/test_repo_config.sh — Tests for lib/repo-config.sh
# =============================================================================
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
source "$TESTS_DIR/framework.sh"
source "$TESTS_DIR/helpers.sh"

setup_test_env
source "$TOOL_ROOT/lib/utils.sh"
source "$TOOL_ROOT/lib/repo-config.sh"

section "_is_valid_repo_alias"

run_test "accepts alphanumeric alias" bash -c "
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/repo-config.sh'
    _is_valid_repo_alias 'pas-ou'
"
run_test "accepts alias with dots and underscores" bash -c "
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/repo-config.sh'
    _is_valid_repo_alias 'my_repo.v2'
"
run_test "rejects alias with spaces" bash -c "
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/repo-config.sh'
    _is_valid_repo_alias 'bad alias' && exit 1 || exit 0
"
run_test "rejects alias with pipe" bash -c "
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/repo-config.sh'
    _is_valid_repo_alias 'bad|alias' && exit 1 || exit 0
"

section "_load_repos_file"

run_test "parses valid repos.conf entry" bash -c "
    export REPOS_FILE='$TEST_TMP/config/repos.conf'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/repo-config.sh'
    echo 'myrepo|myorg/myrepo|/tmp/myrepo' > \$REPOS_FILE
    _load_repos_file
    [[ \"\${_REPO_ALIASES[0]}\" == 'myrepo' ]] && \
    [[ \"\${_REPO_GH[0]}\" == 'myorg/myrepo' ]]
"

run_test "skips comment lines" bash -c "
    export REPOS_FILE='$TEST_TMP/config/repos.conf'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/repo-config.sh'
    printf '# this is a comment\nrealrepo|org/real|/tmp/real\n' > \$REPOS_FILE
    _load_repos_file
    [[ \${#_REPO_ALIASES[@]} -eq 1 ]] && [[ \"\${_REPO_ALIASES[0]}\" == 'realrepo' ]]
"

run_test "skips entries with invalid alias" bash -c "
    export REPOS_FILE='$TEST_TMP/config/repos.conf'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/repo-config.sh'
    echo 'bad alias|org/repo|/tmp' > \$REPOS_FILE
    _load_repos_file 2>/dev/null
    [[ \${#_REPO_ALIASES[@]} -eq 0 ]]
"

run_test "skips entries with wrong field count" bash -c "
    export REPOS_FILE='$TEST_TMP/config/repos.conf'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/repo-config.sh'
    echo 'only-two-fields|org/repo' > \$REPOS_FILE
    _load_repos_file 2>/dev/null
    [[ \${#_REPO_ALIASES[@]} -eq 0 ]]
"

section "load_active_repo"

run_test "sets REPO_PATH and GITHUB_REPO for active alias" bash -c "
    export REPOS_FILE='$TEST_TMP/config/repos.conf'
    export ACTIVE_REPO='testrepo'
    export REPO_PATH=''
    export GITHUB_REPO=''
    mkdir -p '$TEST_TMP/mock_repo'
    echo 'testrepo|testorg/testrepo|$TEST_TMP/mock_repo' > \$REPOS_FILE
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/repo-config.sh'
    load_active_repo 2>/dev/null
    [[ \"\$GITHUB_REPO\" == 'testorg/testrepo' ]]
"

run_test "falls back to first entry when active alias not found" bash -c "
    export REPOS_FILE='$TEST_TMP/config/repos.conf'
    export ACTIVE_REPO='nonexistent'
    echo 'firstrepo|org/first|/tmp/first' > \$REPOS_FILE
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/repo-config.sh'
    load_active_repo 2>/dev/null
    [[ \"\$ACTIVE_REPO\" == 'firstrepo' ]]
"

section "_save_active_repo"

run_test "creates settings.local.conf if missing" bash -c "
    export TOOL_DIR='$TEST_TMP'
    rm -f '$TEST_TMP/config/settings.local.conf'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/repo-config.sh'
    _save_active_repo 'myalias'
    [[ -f '$TEST_TMP/config/settings.local.conf' ]]
"

run_test "writes ACTIVE_REPO to settings.local.conf" bash -c "
    export TOOL_DIR='$TEST_TMP'
    rm -f '$TEST_TMP/config/settings.local.conf'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/repo-config.sh'
    _save_active_repo 'myalias'
    grep -q 'ACTIVE_REPO=\"myalias\"' '$TEST_TMP/config/settings.local.conf'
"

run_test "updates existing ACTIVE_REPO line" bash -c "
    export TOOL_DIR='$TEST_TMP'
    echo 'ACTIVE_REPO=\"old\"' > '$TEST_TMP/config/settings.local.conf'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/repo-config.sh'
    _save_active_repo 'new'
    grep -q 'ACTIVE_REPO=\"new\"' '$TEST_TMP/config/settings.local.conf'
    ! grep -q 'ACTIVE_REPO=\"old\"' '$TEST_TMP/config/settings.local.conf'
"

teardown_test_env
test_summary
