#!/usr/bin/env bash
# =============================================================================
#  checkout.sh — Isolated PR checkout via git worktree
# =============================================================================

# ---------------------------------------------------------------------------
# Fetch PR head from GitHub and create a local branch
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Diagnose a git fetch failure and suggest a fix
# ---------------------------------------------------------------------------
_diagnose_git_fetch_error() {
    local pr_number="$1"
    local error_output="${2:-}"

    if echo "$error_output" | grep -qi "couldn't find remote ref\|remote ref does not exist"; then
        print_error "PR #${pr_number} does not exist or has already been deleted."
        print_info  "Fix: Verify the PR number is correct."
        print_info  "     List open PRs: gh pr list --repo ${GITHUB_REPO}"
    elif echo "$error_output" | grep -qi "repository not found\|remote: not found"; then
        print_error "Remote repository '${GITHUB_REPO}' not found."
        print_info  "Fix: Check config/repos.conf — switch repo via menu option 7."
    elif echo "$error_output" | grep -qi "authentication\|403\|permission denied\|could not read"; then
        print_error "Authentication or permission error fetching PR #${pr_number}."
        print_info  "Fix: Run:  gh auth login"
        print_info  "     Then: gh auth status"
    elif echo "$error_output" | grep -qi "network\|resolve\|connect\|timeout"; then
        print_error "Network error while fetching PR #${pr_number}."
        print_info  "Fix: Check your internet connection and try again."
    elif [[ -n "$error_output" ]]; then
        print_error "Failed to fetch PR #${pr_number}."
        print_info  "Reason: ${error_output}"
        print_info  "Fix: Run manually: cd ${REPO_PATH} && git fetch origin pull/${pr_number}/head:pr-${pr_number}"
    else
        print_error "Failed to fetch PR #${pr_number} (unknown error)."
        print_info  "Fix: Run manually: cd ${REPO_PATH} && git fetch origin pull/${pr_number}/head:pr-${pr_number}"
    fi
}

fetch_pr() {
    local pr_number="$1"
    local branch_name="pr-${pr_number}"

    print_step "Fetching PR #${pr_number} from GitHub..."
    start_spinner "Fetching pull/${pr_number}/head..."

    local fetch_output
    fetch_output=$(cd "$REPO_PATH" && git fetch origin "pull/${pr_number}/head:${branch_name}" 2>&1)
    local exit_code=$?
    stop_spinner

    if [[ $exit_code -ne 0 ]]; then
        # Branch may already exist — try force-updating it
        print_warn "Branch ${branch_name} already exists, updating..."
        fetch_output=$(cd "$REPO_PATH" && git fetch origin "pull/${pr_number}/head:${branch_name}" --force 2>&1)
        exit_code=$?
    fi

    if [[ $exit_code -ne 0 ]]; then
        _diagnose_git_fetch_error "$pr_number" "$fetch_output"
        return 1
    fi

    print_success "PR #${pr_number} fetched as branch '${branch_name}'"
    return 0
}

# ---------------------------------------------------------------------------
# Create an isolated git worktree for the PR
# ---------------------------------------------------------------------------
create_worktree() {
    local pr_number="$1"
    local branch_name="pr-${pr_number}"
    local worktree_path="${CHECKOUTS_DIR}/pr-${pr_number}"

    # If worktree already exists (reuse path), just return it
    if [[ -d "$worktree_path" ]]; then
        echo "$worktree_path"
        return 0
    fi

    print_step "Creating isolated worktree at: ${worktree_path}"
    start_spinner "Creating worktree..."

    (cd "$REPO_PATH" && git worktree add "$worktree_path" "$branch_name" 2>&1)
    local exit_code=$?
    stop_spinner

    if [[ $exit_code -ne 0 ]]; then
        print_error "Failed to create worktree for PR #${pr_number}"
        return 1
    fi

    print_success "Worktree created: ${worktree_path}"
    echo "$worktree_path"
    return 0
}

# ---------------------------------------------------------------------------
# Find the merge base between PR branch and its target base
# Tries GitHub API first (most accurate), falls back to local git merge-base
# ---------------------------------------------------------------------------
find_merge_base() {
    local pr_number="$1"
    local base_branch="${2:-$DEFAULT_BASE_BRANCH}"
    local branch_name="pr-${pr_number}"

    # Strategy 1: Ask GitHub API for the merge-base SHA directly
    local api_base_sha
    api_base_sha=$(gh api "repos/${GITHUB_REPO}/pulls/${pr_number}" \
        --jq '.base.sha' 2>/dev/null)
    if [[ -n "$api_base_sha" && "$api_base_sha" != "null" ]]; then
        echo "$api_base_sha"
        return 0
    fi

    # Strategy 2: Local git merge-base against the PR's target base branch
    (cd "$REPO_PATH" && git fetch origin "$base_branch" --quiet 2>/dev/null) || true
    local merge_base
    merge_base=$(cd "$REPO_PATH" && git merge-base "$branch_name" "origin/${base_branch}" 2>/dev/null)

    if [[ -n "$merge_base" ]]; then
        echo "$merge_base"
        return 0
    fi

    # Strategy 3: Fallback to origin/main
    (cd "$REPO_PATH" && git fetch origin "${DEFAULT_BASE_BRANCH}" --quiet 2>/dev/null) || true
    merge_base=$(cd "$REPO_PATH" && git merge-base "$branch_name" "origin/${DEFAULT_BASE_BRANCH}" 2>/dev/null)

    if [[ -z "$merge_base" ]]; then
        print_error "Could not determine merge base for PR #${pr_number}"
        return 1
    fi

    echo "$merge_base"
}

# ---------------------------------------------------------------------------
# List all files changed in the PR (filtered by relevant extensions)
# ---------------------------------------------------------------------------
list_changed_files() {
    local pr_number="$1"
    local merge_base="$2"
    local branch_name="pr-${pr_number}"

    (cd "$REPO_PATH" && git diff "${merge_base}" "${branch_name}" --name-only 2>/dev/null) \
        | grep -E '\.(ts|html|scss|json)$' \
        | grep -v '\.spec\.ts$' \
        | sort
}

# ---------------------------------------------------------------------------
# List ALL changed files (including spec, for karma checks)
# ---------------------------------------------------------------------------
list_all_changed_files() {
    local pr_number="$1"
    local merge_base="$2"
    local branch_name="pr-${pr_number}"

    (cd "$REPO_PATH" && git diff "${merge_base}" "${branch_name}" --name-only 2>/dev/null) | sort
}

# ---------------------------------------------------------------------------
# List changed spec files specifically
# ---------------------------------------------------------------------------
list_changed_spec_files() {
    local pr_number="$1"
    local merge_base="$2"
    local branch_name="pr-${pr_number}"

    (cd "$REPO_PATH" && git diff "${merge_base}" "${branch_name}" --name-only 2>/dev/null) \
        | grep '\.spec\.ts$' \
        | sort
}

# ---------------------------------------------------------------------------
# Get the diff of a specific file against merge base
# ---------------------------------------------------------------------------
get_file_diff() {
    local pr_number="$1"
    local merge_base="$2"
    local file_path="$3"
    local branch_name="pr-${pr_number}"

    (cd "$REPO_PATH" && git diff "${merge_base}" "${branch_name}" -- "$file_path" 2>/dev/null)
}

# ---------------------------------------------------------------------------
# Remove a PR worktree and optionally prune the local branch
# ---------------------------------------------------------------------------
remove_worktree() {
    local pr_number="$1"
    local worktree_path="${CHECKOUTS_DIR}/pr-${pr_number}"
    local branch_name="pr-${pr_number}"

    if [[ ! -d "$worktree_path" ]]; then
        print_warn "No worktree found at: ${worktree_path}"
        return 0
    fi

    print_step "Removing worktree for PR #${pr_number}..."
    (cd "$REPO_PATH" && git worktree remove "$worktree_path" --force 2>&1) || rm -rf "$worktree_path"
    (cd "$REPO_PATH" && git worktree prune 2>/dev/null) || true

    if confirm_prompt "Also delete local branch '${branch_name}'?"; then
        (cd "$REPO_PATH" && git branch -D "$branch_name" 2>/dev/null) && \
            print_success "Branch '${branch_name}' deleted." || \
            print_warn "Branch '${branch_name}' not found or could not be deleted."
    fi

    print_success "Worktree removed: ${worktree_path}"
}

# ---------------------------------------------------------------------------
# List all existing PR checkouts
# ---------------------------------------------------------------------------
list_checkouts() {
    if [[ ! -d "$CHECKOUTS_DIR" ]] || [[ -z "$(ls -A "$CHECKOUTS_DIR" 2>/dev/null)" ]]; then
        print_info "No existing PR checkouts found."
        return
    fi

    echo ""
    printf "  ${BOLD}%-15s %-30s %-10s${RESET}\n" "PR" "Path" "Size"
    print_rule
    for dir in "$CHECKOUTS_DIR"/pr-*/; do
        [[ -d "$dir" ]] || continue
        local pr_name
        pr_name=$(basename "$dir")
        local size
        size=$(du -sh "$dir" 2>/dev/null | cut -f1)
        printf "  %-15s %-30s %-10s\n" "$pr_name" "$dir" "$size"
    done
    echo ""
}

# ---------------------------------------------------------------------------
# Diagnose a gh API failure and suggest a fix
# ---------------------------------------------------------------------------
_diagnose_api_fetch_error() {
    local pr_number="$1"
    local error_output="${2:-}"

    if echo "$error_output" | grep -qi "404\|not found\|could not resolve"; then
        print_error "PR #${pr_number} not found in '${GITHUB_REPO}'."
        print_info  "Fix: Check the PR number is correct."
        print_info  "     Active repo: ${GITHUB_REPO} — switch via menu option 7."
    elif echo "$error_output" | grep -qi "401\|403\|unauthorized\|forbidden\|authentication"; then
        print_error "Authentication failed — no access to '${GITHUB_REPO}'."
        print_info  "Fix: Run:  gh auth login"
        print_info  "     Then: gh auth status"
    elif echo "$error_output" | grep -qi "network\|resolve\|connect\|timeout\|ssl"; then
        print_error "Network error while contacting GitHub API."
        print_info  "Fix: Check your internet connection and try again."
    elif ! command -v gh &>/dev/null; then
        print_error "gh CLI not found."
        print_info  "Fix: Run ./setup.sh to install it."
    elif [[ -n "$error_output" ]]; then
        print_error "Unexpected GitHub API error for PR #${pr_number}."
        print_info  "Reason: ${error_output}"
        print_info  "Fix: Run: gh api repos/${GITHUB_REPO}/pulls/${pr_number}"
    else
        print_error "Empty response for PR #${pr_number} — it may not exist."
        print_info  "Fix: Verify: gh pr view ${pr_number} --repo ${GITHUB_REPO}"
    fi
}

# ---------------------------------------------------------------------------
# Fetch PR metadata from GitHub API
# ---------------------------------------------------------------------------
fetch_pr_metadata() {
    local pr_number="$1"
    local api_output api_err

    api_output=$(gh api "repos/${GITHUB_REPO}/pulls/${pr_number}" \
        --jq '{title: .title, author: .user.login, base: .base.ref, state: .state, created_at: .created_at, body: .body}' \
        2>/tmp/_pr_fetch_err_$$)
    local exit_code=$?
    api_err=$(cat /tmp/_pr_fetch_err_$$ 2>/dev/null); rm -f /tmp/_pr_fetch_err_$$

    if [[ $exit_code -ne 0 || -z "$api_output" ]]; then
        _diagnose_api_fetch_error "$pr_number" "$api_err"
        return 1
    fi

    echo "$api_output"
}
