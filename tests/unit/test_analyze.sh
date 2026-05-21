#!/usr/bin/env bash
# =============================================================================
#  tests/unit/test_analyze.sh — Tests for lib/analyze.sh
# =============================================================================
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
source "$TESTS_DIR/framework.sh"
source "$TESTS_DIR/helpers.sh"

setup_test_env
source "$TOOL_ROOT/lib/utils.sh"
source "$TOOL_ROOT/lib/analyze.sh"

# Create a fake worktree with test files
WORKTREE="$TEST_TMP/worktree"
mkdir -p "$WORKTREE/src/app"

section "add_finding — counter management"

run_test "BLOCKER increments COUNT_BLOCKER" bash -c "
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/analyze.sh'
    declare -a FINDINGS=(); COUNT_BLOCKER=0; COUNT_MAJOR=0; COUNT_MINOR=0
    add_finding 'BLOCKER' 'COMP-06' 'file.ts' '10' 'match' 'msg'
    [[ \$COUNT_BLOCKER -eq 1 ]]
"

run_test "MAJOR increments COUNT_MAJOR" bash -c "
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/analyze.sh'
    declare -a FINDINGS=(); COUNT_BLOCKER=0; COUNT_MAJOR=0; COUNT_MINOR=0
    add_finding 'MAJOR' 'CLEAN-04' 'file.ts' '5' 'match' 'msg'
    [[ \$COUNT_MAJOR -eq 1 ]]
"

run_test "MINOR increments COUNT_MINOR" bash -c "
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/analyze.sh'
    declare -a FINDINGS=(); COUNT_BLOCKER=0; COUNT_MAJOR=0; COUNT_MINOR=0
    add_finding 'MINOR' 'NAME-02' 'file.ts' '3' 'match' 'msg'
    [[ \$COUNT_MINOR -eq 1 ]]
"

run_test "finding stored in FINDINGS array with correct format" bash -c "
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/analyze.sh'
    declare -a FINDINGS=(); COUNT_BLOCKER=0; COUNT_MAJOR=0; COUNT_MINOR=0
    add_finding 'MAJOR' 'CLEAN-04' 'src/app.ts' '42' 'console.log(x)' 'Remove logs'
    echo \"\${FINDINGS[0]}\" | grep -q 'MAJOR|CLEAN-04|src/app.ts|42'
"

section "scan_console_log — detection"

run_test "detects console.log in .ts file" bash -c "
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/analyze.sh'
    declare -a FINDINGS=(); COUNT_BLOCKER=0; COUNT_MAJOR=0; COUNT_MINOR=0
    mkdir -p '$WORKTREE/src'
    echo 'console.log(\"debug\");' > '$WORKTREE/src/test.ts'
    scan_console_log '$WORKTREE' 'src/test.ts'
    [[ \$COUNT_MAJOR -eq 1 ]]
"

run_test "detects console.warn in .ts file" bash -c "
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/analyze.sh'
    declare -a FINDINGS=(); COUNT_BLOCKER=0; COUNT_MAJOR=0; COUNT_MINOR=0
    echo 'console.warn(\"warning\");' > '$WORKTREE/src/warn.ts'
    scan_console_log '$WORKTREE' 'src/warn.ts'
    [[ \$COUNT_MAJOR -eq 1 ]]
"

run_test "ignores commented-out console.log" bash -c "
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/analyze.sh'
    declare -a FINDINGS=(); COUNT_BLOCKER=0; COUNT_MAJOR=0; COUNT_MINOR=0
    echo '// console.log(\"commented\");' > '$WORKTREE/src/commented.ts'
    scan_console_log '$WORKTREE' 'src/commented.ts'
    [[ \$COUNT_MAJOR -eq 0 ]]
"

run_test "ignores console.log in non-.ts files" bash -c "
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/analyze.sh'
    declare -a FINDINGS=(); COUNT_BLOCKER=0; COUNT_MAJOR=0; COUNT_MINOR=0
    echo 'console.log(\"debug\");' > '$WORKTREE/src/test.html'
    scan_console_log '$WORKTREE' 'src/test.html'
    [[ \$COUNT_MAJOR -eq 0 ]]
"

section "scan_commented_code — detection"

run_test "detects commented-out this. usage" bash -c "
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/analyze.sh'
    declare -a FINDINGS=(); COUNT_BLOCKER=0; COUNT_MAJOR=0; COUNT_MINOR=0
    echo '// this.service.load();' > '$WORKTREE/src/comp.ts'
    scan_commented_code '$WORKTREE' 'src/comp.ts'
    [[ \$COUNT_MAJOR -ge 1 ]]
"

run_test "detects commented-out subscribe call" bash -c "
    source '$TOOL_ROOT/lib/utils.sh'; source '$TOOL_ROOT/lib/analyze.sh'
    declare -a FINDINGS=(); COUNT_BLOCKER=0; COUNT_MAJOR=0; COUNT_MINOR=0
    echo '// this.obs$.subscribe(x => this.data = x);' > '$WORKTREE/src/comp2.ts'
    scan_commented_code '$WORKTREE' 'src/comp2.ts'
    [[ \$COUNT_MAJOR -ge 1 ]]
"

teardown_test_env
test_summary
