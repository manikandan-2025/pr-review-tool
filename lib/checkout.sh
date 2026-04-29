#!/usr/bin/env bash
# =============================================================================
#  checkout.sh — Isolated PR checkout via git worktree
# =============================================================================

# ---------------------------------------------------------------------------
# Fetch PR head from GitHub and create a local branch
# ---------------------------------------------------------------------------
fetch_pr() {
    local pr_number="$1"
    local branch_name="pr-${pr_number}"

    print_step "Fetching PR #${pr_number} from GitHub..."
    start_spinner "Fetching pull/${pr_number}/head..."

    (cd "$REPO_PATH" && git fetch origin "pull/${pr_number}/head:${branch_name}" 2>&1)
    local exit_code=$?
    stop_spinner

    if [[ $exit_code -ne 0 ]]; then
        # Branch may already exist — try updating it
        print_warn "Branch ${branch_name} already exists, updating..."
        (cd "$REPO_PATH" && git fetch origin "pull/${pr_number}/head:${branch_name}" --force 2>&1)
        exit_code=$?
    fi

    if [[ $exit_code -ne 0 ]]; then
        print_error "Failed to fetch PR #${pr_number}. Check your network and gh auth."
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
# Fetch PR metadata from GitHub API
# ---------------------------------------------------------------------------
fetch_pr_metadata() {
    local pr_number="$1"
    gh api "repos/${GITHUB_REPO}/pulls/${pr_number}" \
        --jq '{title: .title, author: .user.login, base: .base.ref, state: .state, created_at: .created_at, body: .body}' \
        2>/dev/null
}
