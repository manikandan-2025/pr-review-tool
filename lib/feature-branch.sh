#!/usr/bin/env bash
# =============================================================================
#  feature-branch.sh — Checkout a feature branch from main and work on it
#
#  Workflow:
#    1. User provides a new branch name
#    2. Fetch latest origin/main (or DEFAULT_BASE_BRANCH)
#    3. Create a new local branch from origin/main
#    4. Create an isolated git worktree for it
#    5. Open an interactive shell (or editor) inside the worktree
#
#  Worktrees are stored in:  $CHECKOUTS_DIR/feature-<safe-branch-name>/
#  Local branch name used:   feature/<original-branch-name>
# =============================================================================

# ---------------------------------------------------------------------------
# Internal: sanitise a branch name to a filesystem-safe directory segment
# ---------------------------------------------------------------------------
_safe_name() {
    echo "$1" | tr '/' '-' | tr ' ' '_' | sed 's/[^A-Za-z0-9._-]/_/g'
}

# ---------------------------------------------------------------------------
# List existing feature-branch worktrees created by this tool
# ---------------------------------------------------------------------------
list_feature_checkouts() {
    local found=false
    for dir in "${CHECKOUTS_DIR}"/feature-*/; do
        [[ -d "$dir" ]] || continue
        found=true
        local dname
        dname=$(basename "$dir")
        # Recover the original branch name from the local git HEAD inside the worktree
        local head_ref
        head_ref=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null || echo "(detached)")
        local size
        size=$(du -sh "$dir" 2>/dev/null | cut -f1)
        printf "  %-40s  ${DIM}%-35s  %s${RESET}\n" "$dname" "$head_ref" "$size"
    done
    if [[ "$found" == "false" ]]; then
        print_info "No feature-branch checkouts found."
    fi
}

# ---------------------------------------------------------------------------
# checkout_feature_branch — main workflow
# ---------------------------------------------------------------------------
checkout_feature_branch() {
    print_header "Checkout Feature Branch from ${DEFAULT_BASE_BRANCH}  [repo: ${BOLD}${ACTIVE_REPO}${RESET}${CYAN}]"

    if [[ ! -d "$REPO_PATH" ]]; then
        print_error "Repository not found at: ${REPO_PATH}"
        print_info "Use option 7 (Manage Repositories) to set the correct path."
        return 1
    fi

    # Show existing checkouts
    echo -e "  ${BOLD}Existing feature-branch checkouts:${RESET}"
    list_feature_checkouts
    echo ""

    # --- Ask for the new branch name ---
    local branch_name
    branch_name=$(prompt_input "New feature branch name (e.g. feat/my-feature)" "")
    if [[ -z "$branch_name" ]]; then
        print_info "Cancelled."
        return 0
    fi

    # Normalise: strip a leading "feature/" or "feat/" prefix for the display
    # but keep the full name as the actual branch
    local safe
    safe=$(_safe_name "$branch_name")
    local worktree_path="${CHECKOUTS_DIR}/feature-${safe}"
    local local_branch="feature/${safe}"

    # --- Handle existing worktree ---
    if [[ -d "$worktree_path" ]]; then
        print_warn "Checkout already exists: ${worktree_path}"
        if confirm_prompt "Re-open existing checkout?"; then
            print_success "Re-using: ${worktree_path}"
            _open_worktree_shell "$worktree_path" "$branch_name"
            return 0
        else
            print_step "Removing existing worktree..."
            (cd "$REPO_PATH" && git worktree remove "$worktree_path" --force 2>/dev/null) || rm -rf "$worktree_path"
            (cd "$REPO_PATH" && git branch -D "$local_branch" 2>/dev/null) || true
            (cd "$REPO_PATH" && git worktree prune 2>/dev/null) || true
        fi
    fi

    # --- Fetch latest base branch ---
    print_step "Fetching latest origin/${DEFAULT_BASE_BRANCH}..."
    start_spinner "Fetching ${DEFAULT_BASE_BRANCH}..."
    (cd "$REPO_PATH" && git fetch origin "${DEFAULT_BASE_BRANCH}" --quiet 2>&1)
    local fetch_exit=$?
    stop_spinner

    if [[ $fetch_exit -ne 0 ]]; then
        print_error "Failed to fetch origin/${DEFAULT_BASE_BRANCH}. Check your network and gh auth."
        return 1
    fi
    print_success "origin/${DEFAULT_BASE_BRANCH} is up to date"

    # --- Check if local branch already exists ---
    if (cd "$REPO_PATH" && git show-ref --quiet "refs/heads/${local_branch}" 2>/dev/null); then
        print_warn "Local branch '${local_branch}' already exists."
        if confirm_prompt "Delete existing local branch and recreate from ${DEFAULT_BASE_BRANCH}?"; then
            (cd "$REPO_PATH" && git branch -D "$local_branch" 2>/dev/null) || true
        else
            print_info "Using existing local branch '${local_branch}'"
        fi
    fi

    # --- Create local branch from origin/main ---
    print_step "Creating '${local_branch}' from origin/${DEFAULT_BASE_BRANCH}..."
    (cd "$REPO_PATH" && git branch "${local_branch}" "origin/${DEFAULT_BASE_BRANCH}" 2>&1)
    local branch_exit=$?

    if [[ $branch_exit -ne 0 ]]; then
        # Branch may have already existed and not been deleted — try to proceed
        print_warn "Could not create branch (may already exist). Attempting to continue..."
    else
        print_success "Branch '${local_branch}' created from origin/${DEFAULT_BASE_BRANCH}"
    fi

    # --- Create worktree ---
    print_step "Creating isolated worktree at: ${worktree_path}"
    start_spinner "Creating worktree..."
    (cd "$REPO_PATH" && git worktree add "$worktree_path" "$local_branch" 2>&1)
    local wt_exit=$?
    stop_spinner

    if [[ $wt_exit -ne 0 ]]; then
        print_error "Failed to create worktree. See output above."
        (cd "$REPO_PATH" && git branch -D "$local_branch" 2>/dev/null) || true
        return 1
    fi

    print_success "Worktree ready: ${worktree_path}"
    echo ""
    echo -e "  ${DIM}Branch:   ${RESET}${local_branch}"
    echo -e "  ${DIM}Based on: ${RESET}origin/${DEFAULT_BASE_BRANCH}"
    echo -e "  ${DIM}Repo:     ${RESET}${GITHUB_REPO}  (${REPO_PATH})"
    echo ""

    _open_worktree_shell "$worktree_path" "$branch_name"
}

# ---------------------------------------------------------------------------
# _open_worktree_shell — offer ways to "work" inside the worktree
# ---------------------------------------------------------------------------
_open_worktree_shell() {
    local worktree_path="$1"
    local branch_name="$2"

    echo -e "  ${BOLD}How would you like to work on ${CYAN}${branch_name}${RESET}${BOLD}?${RESET}"
    echo -e "  ${CYAN}1)${RESET} Open an interactive shell inside the worktree"
    echo -e "  ${CYAN}2)${RESET} Open in \$EDITOR (${EDITOR:-nano})"
    echo -e "  ${CYAN}3)${RESET} Print the path only"
    echo -e "  ${CYAN}4)${RESET} Return to menu"
    echo ""
    printf "  ${BOLD}→${RESET} Enter choice [1-4]: "
    read -r work_choice

    case "$work_choice" in
        1)
            print_info "Launching shell in: ${worktree_path}"
            print_info "Type ${BOLD}exit${RESET} to return to the PR Review Tool."
            echo ""
            (cd "$worktree_path" && exec "${SHELL:-bash}" --login)
            ;;
        2)
            if command -v "${EDITOR:-nano}" &>/dev/null; then
                "${EDITOR:-nano}" "$worktree_path"
            else
                print_warn "Editor '${EDITOR:-nano}' not found. Set \$EDITOR to your preferred editor."
            fi
            ;;
        3)
            echo ""
            echo -e "  ${BOLD}Worktree path:${RESET}"
            echo -e "  ${GREEN}${worktree_path}${RESET}"
            echo ""
            ;;
        4|"")
            print_info "Returned to menu."
            ;;
        *)
            print_info "Returned to menu."
            ;;
    esac
}

# ---------------------------------------------------------------------------
# remove_feature_worktree — clean up one or all feature-branch worktrees
# ---------------------------------------------------------------------------
remove_feature_worktree() {
    print_header "Remove Feature Branch Checkout"

    echo -e "  ${BOLD}Current feature-branch checkouts:${RESET}"
    list_feature_checkouts
    echo ""

    local branch_input
    branch_input=$(prompt_input "Branch safe-name to remove (or 'all', Enter to cancel)" "")
    if [[ -z "$branch_input" ]]; then
        print_info "Cancelled."
        return 0
    fi

    if [[ "$branch_input" == "all" ]]; then
        if confirm_prompt "Remove ALL feature-branch checkouts? This cannot be undone."; then
            for dir in "${CHECKOUTS_DIR}"/feature-*/; do
                [[ -d "$dir" ]] || continue
                local safe
                safe=$(basename "$dir" | sed 's/^feature-//')
                local lb="feature/${safe}"
                (cd "$REPO_PATH" && git worktree remove "$dir" --force 2>/dev/null) || rm -rf "$dir"
                (cd "$REPO_PATH" && git branch -D "$lb" 2>/dev/null) || true
            done
            (cd "$REPO_PATH" && git worktree prune 2>/dev/null) || true
            print_success "All feature-branch checkouts removed."
        fi
        return 0
    fi

    local safe_input
    safe_input=$(_safe_name "$branch_input")
    local worktree_path="${CHECKOUTS_DIR}/feature-${safe_input}"
    local local_branch="feature/${safe_input}"

    if [[ ! -d "$worktree_path" ]]; then
        print_warn "No checkout found for: ${branch_input}"
        print_info "Available checkouts are listed above."
        return 0
    fi

    (cd "$REPO_PATH" && git worktree remove "$worktree_path" --force 2>/dev/null) || rm -rf "$worktree_path"
    (cd "$REPO_PATH" && git worktree prune 2>/dev/null) || true
    if confirm_prompt "Also delete local branch '${local_branch}'?"; then
        (cd "$REPO_PATH" && git branch -D "$local_branch" 2>/dev/null) && \
            print_success "Branch '${local_branch}' deleted." || \
            print_warn "Branch '${local_branch}' not found or already deleted."
    fi
    print_success "Removed feature checkout: ${worktree_path}"
}
