#!/usr/bin/env bash
# =============================================================================
#  tests/unit/test_jira.sh — Tests for lib/jira-context.sh
# =============================================================================
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
source "$TESTS_DIR/framework.sh"
source "$TESTS_DIR/helpers.sh"

setup_test_env
source "$TOOL_ROOT/lib/utils.sh"
source "$TOOL_ROOT/lib/jira-context.sh"

section "_jira_save_setting — basic writes"

run_test "writes new key to target file" bash -c "
    export TOOL_DIR='$TEST_TMP'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/jira-context.sh'
    target='$TEST_TMP/config/settings.conf'
    _jira_save_setting 'TEST_KEY' 'hello' 2>/dev/null
    grep -q 'TEST_KEY' \"\$target\"
"

run_test "updates existing key without duplicating" bash -c "
    export TOOL_DIR='$TEST_TMP'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/jira-context.sh'
    target='$TEST_TMP/config/settings.conf'
    echo 'MY_KEY=\"old_val\"' > \"\$target\"
    _jira_save_setting 'MY_KEY' 'new_val' 2>/dev/null
    count=\$(grep -c 'MY_KEY' \"\$target\")
    [[ \"\$count\" -eq 1 ]] && grep -q 'new_val' \"\$target\"
"

run_test "JIRA_PAT goes to secrets.conf not settings.conf" bash -c "
    export TOOL_DIR='$TEST_TMP'
    cp '$TOOL_ROOT/config/secrets.conf.example' '$TEST_TMP/config/secrets.conf' 2>/dev/null || \
        echo '# secrets' > '$TEST_TMP/config/secrets.conf'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/jira-context.sh'
    _jira_save_setting 'JIRA_PAT' 'mytoken' 2>/dev/null
    grep -q 'JIRA_PAT' '$TEST_TMP/config/secrets.conf'
"

run_test "secrets.conf gets chmod 600 when JIRA_PAT saved" bash -c "
    export TOOL_DIR='$TEST_TMP'
    echo '# secrets' > '$TEST_TMP/config/secrets.conf'
    chmod 644 '$TEST_TMP/config/secrets.conf'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/jira-context.sh'
    _jira_save_setting 'JIRA_PAT' 'mytoken' 2>/dev/null
    p=\$(stat -c '%a' '$TEST_TMP/config/secrets.conf' 2>/dev/null || stat -f '%Lp' '$TEST_TMP/config/secrets.conf')
    [[ \"\$p\" == '600' ]]
"

section "_jira_save_setting — injection prevention"

run_test "rejects values containing newlines" bash -c "
    export TOOL_DIR='$TEST_TMP'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/jira-context.sh'
    _jira_save_setting 'BAD_KEY' \$'line1\nline2' 2>/dev/null && exit 1 || exit 0
"

run_test "single-quotes value containing double quote" bash -c "
    export TOOL_DIR='$TEST_TMP'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/jira-context.sh'
    target='$TEST_TMP/config/settings.conf'
    _jira_save_setting 'QUOTE_KEY' 'val\"with\"quotes' 2>/dev/null
    grep -q 'QUOTE_KEY' \"\$target\"
    # Value must be in single quotes (not raw with double-quotes that could execute)
    grep 'QUOTE_KEY' \"\$target\" | grep -q \"'\"
"

run_test "value containing pipe character does not break config" bash -c "
    export TOOL_DIR='$TEST_TMP'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/jira-context.sh'
    target='$TEST_TMP/config/settings.conf'
    _jira_save_setting 'PIPE_KEY' 'val|with|pipes' 2>/dev/null
    grep -q 'PIPE_KEY' \"\$target\"
"

section "fetch_jira_issue — uses curl -K (not -H with token in args)"

run_test "curl config file used (-K flag)" bash -c "
    export PATH='$TEST_BIN:$PATH'
    export TOOL_DIR='$TEST_TMP'
    export JIRA_BASE_URL='https://jira.example.com'
    export JIRA_PAT='test-secret-token'
    export JIRA_API_VERSION='2'
    export JIRA_AC_FIELD=''
    export MOCK_CURL_HTTP_CODE='200'
    export MOCK_CURL_RESPONSE='{\"fields\":{\"summary\":\"Test Story\",\"description\":\"Desc\",\"issuetype\":{\"name\":\"Story\"},\"status\":{\"name\":\"In Progress\"},\"labels\":[],\"components\":[],\"attachment\":[]}}'

    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/jira-context.sh'

    # The curl mock checks for -K flag usage — verify source code uses -K
    grep -q '\-K' '$TOOL_ROOT/lib/jira-context.sh'
"

run_test "JIRA_PAT not passed as -H Authorization in argv" bash -c "
    # Verify the source no longer has -H Authorization: Bearer in fetch_jira_issue
    # (it should use curl config file -K instead)
    ! grep -A3 'curl.*max-time.*15' '$TOOL_ROOT/lib/jira-context.sh' | grep -q '\"Authorization: Bearer'
"

section "gather_jira_context — skip when user declines"

run_test "returns 0 and empty result when user says no" bash -c "
    export PATH='$TEST_BIN:$PATH'
    export TOOL_DIR='$TEST_TMP'
    export JIRA_BASE_URL='https://jira.example.com'
    export JIRA_PAT='tok'
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/jira-context.sh'
    # Override confirm_prompt to return 'no'
    confirm_prompt() { return 1; }
    prompt_input() { echo 'PAS-123'; }
    JIRA_CONTEXT_RESULT='init'
    gather_jira_context 2>/dev/null
    [[ -z \"\$JIRA_CONTEXT_RESULT\" ]]
"

teardown_test_env
test_summary
