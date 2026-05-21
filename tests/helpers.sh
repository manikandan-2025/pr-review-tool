#!/usr/bin/env bash
# =============================================================================
#  tests/helpers.sh — Test environment setup, teardown, and mock commands
# =============================================================================

TEST_TMP=""
TEST_BIN=""

# ---------------------------------------------------------------------------
# setup_test_env — create an isolated temp workspace mimicking the tool layout
# ---------------------------------------------------------------------------
setup_test_env() {
    TEST_TMP=$(mktemp -d)
    TEST_BIN=$(mktemp -d)

    export TOOL_DIR="$TEST_TMP"
    export REPORTS_DIR="$TEST_TMP/reports"
    export CHECKOUTS_DIR="$TEST_TMP/checkouts"
    export ACTIVE_REPO="testrepo"
    export GITHUB_REPO="testorg/testrepo"
    export DEFAULT_BASE_BRANCH="main"
    export JIRA_API_VERSION="2"
    export JIRA_BASE_URL="https://jira.example.com"
    export JIRA_PAT="test-jira-pat"
    export JIRA_AC_FIELD=""
    export INSTRUCTIONS_FILE="$TEST_TMP/pr-review.instructions.md"
    export REPOS_FILE="$TEST_TMP/config/repos.conf"
    export EDITOR="true"   # no-op editor

    # Create mock git repo for REPO_PATH
    export REPO_PATH="$TEST_TMP/mock_repo"
    mkdir -p "$REPO_PATH"
    mkdir -p "$TEST_TMP/config"

    # Default repos.conf
    echo "testrepo|testorg/testrepo|$REPO_PATH" > "$REPOS_FILE"

    # Default settings.conf stub
    cat > "$TEST_TMP/config/settings.conf" << CONF
ACTIVE_REPO="testrepo"
DEFAULT_BASE_BRANCH="main"
REPORTS_DIR="$TEST_TMP/reports"
CHECKOUTS_DIR="$TEST_TMP/checkouts"
INSTRUCTIONS_FILE="$TEST_TMP/pr-review.instructions.md"
REPOS_FILE="$TEST_TMP/config/repos.conf"
CONF

    # Blank instructions file
    cat > "$INSTRUCTIONS_FILE" << 'INS'
# Code Review Guidelines
| Rule | Severity | Violation |
|------|----------|-----------|
| CLEAN-04 | Major | console.log left in code |
| COMP-06 | Blocker | Subscription without OnDestroy |
INS

    # Prepend TEST_BIN to PATH for mocks
    export PATH="$TEST_BIN:$PATH"
    setup_mock_commands
}

teardown_test_env() {
    [[ -n "$TEST_TMP" && -d "$TEST_TMP" ]] && rm -rf "$TEST_TMP"
    [[ -n "$TEST_BIN" && -d "$TEST_BIN" ]] && rm -rf "$TEST_BIN"
}

# ---------------------------------------------------------------------------
# Mock commands — configurable via env vars
# ---------------------------------------------------------------------------
setup_mock_commands() {
    # mock: gh
    cat > "$TEST_BIN/gh" << 'GHEOF'
#!/usr/bin/env bash
# Reconstruct full arg string for matching
ARGS="$*"
case "$ARGS" in
    "auth status"*)
        exit "${MOCK_GH_AUTH_EXIT:-0}" ;;
    "auth login"*)
        exit "${MOCK_GH_AUTH_LOGIN_EXIT:-0}" ;;
    "copilot --version"*|"copilot -h"*)
        echo "1.0.0"; exit 0 ;;
    "extension list"*)
        echo "github/gh-copilot"; exit 0 ;;
    "copilot -- -p"*|"copilot --"*)
        echo "${MOCK_COPILOT_OUTPUT:-AI: No issues found.}"; exit "${MOCK_COPILOT_EXIT:-0}" ;;
    "api repos/"*"pulls/"*)
        echo "${MOCK_PR_META:-{\"title\":\"Test PR\",\"author\":\"testuser\",\"base\":\"main\",\"state\":\"open\",\"created_at\":\"2024-01-01T00:00:00Z\",\"body\":\"Test body\"}}"
        exit "${MOCK_GH_API_EXIT:-0}" ;;
    "pr list"*)
        echo "42Test PROPEN"; exit 0 ;;
    *)
        exit "${MOCK_GH_DEFAULT_EXIT:-0}" ;;
esac
GHEOF
    chmod +x "$TEST_BIN/gh"

    # mock: git
    cat > "$TEST_BIN/git" << 'GITEOF'
#!/usr/bin/env bash
case "$1" in
    "fetch")
        [[ "${MOCK_GIT_FETCH_EXIT:-0}" -ne 0 ]] && echo "${MOCK_GIT_FETCH_ERR:-fetch error}" >&2
        exit "${MOCK_GIT_FETCH_EXIT:-0}" ;;
    "worktree")
        case "$2" in
            "add")    mkdir -p "$4" 2>/dev/null; exit "${MOCK_GIT_WT_ADD_EXIT:-0}" ;;
            "remove") exit "${MOCK_GIT_WT_REMOVE_EXIT:-0}" ;;
            "prune")  exit 0 ;;
        esac ;;
    "merge-base")
        echo "${MOCK_GIT_MERGE_BASE:-abc123def456}"; exit 0 ;;
    "diff")
        printf '%s\n' "${MOCK_GIT_DIFF_FILES:-src/app/test.ts}"; exit 0 ;;
    "branch")   exit 0 ;;
    "config")   echo "${MOCK_GIT_CONFIG_VALUE:-testuser}"; exit 0 ;;
    "-C")
        # git -C <dir> <subcmd> ...
        case "$3" in
            "ls-files") exit "${MOCK_GIT_LS_FILES_EXIT:-1}" ;;
            "fetch"|"worktree"|"branch"|"merge-base"|"diff") shift; exec "$TEST_BIN/git" "$@" ;;
            *) exit 0 ;;
        esac ;;
    *) exit 0 ;;
esac
GITEOF
    chmod +x "$TEST_BIN/git"

    # mock: curl
    cat > "$TEST_BIN/curl" << 'CURLEOF'
#!/usr/bin/env bash
# Check if -K flag is used (secure credential passing)
USE_K=0
for arg in "$@"; do [[ "$arg" == "-K" ]] && USE_K=1; done
export MOCK_CURL_USED_K_FLAG="$USE_K"
echo "${MOCK_CURL_RESPONSE:-{\"displayName\":\"Jira Test User\"}}"
echo "__HTTP_CODE__:${MOCK_CURL_HTTP_CODE:-200}"
exit "${MOCK_CURL_EXIT:-0}"
CURLEOF
    chmod +x "$TEST_BIN/curl"

    # mock: stat (to make permission tests portable)
    # Only mock if needed — let real stat handle it
}

# Source all lib files into the current shell
source_libs() {
    local tool_dir="${1:-$TOOL_DIR}"
    source "$tool_dir/../lib/utils.sh"       2>/dev/null || true
    source "$tool_dir/../lib/repo-config.sh" 2>/dev/null || true
    source "$tool_dir/../lib/checkout.sh"    2>/dev/null || true
    source "$tool_dir/../lib/analyze.sh"     2>/dev/null || true
    source "$tool_dir/../lib/copilot.sh"     2>/dev/null || true
    source "$tool_dir/../lib/report.sh"      2>/dev/null || true
    source "$tool_dir/../lib/instructions.sh" 2>/dev/null || true
    source "$tool_dir/../lib/jira-context.sh" 2>/dev/null || true
}

# Resolve TESTS_DIR and TOOL_ROOT from this file location
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
