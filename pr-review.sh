#!/usr/bin/env bash
# =============================================================================
#  pr-review.sh — Interactive PR Code Review Tool (multi-repo)
#
#  Usage:
#    ./pr-review.sh              → interactive menu
#    ./pr-review.sh --pr <N>     → directly review PR number N
#    ./pr-review.sh --help       → show usage
#
#  Requirements: git, gh (GitHub CLI with auth), bash 4+
# =============================================================================

# NOTE: do NOT use set -euo pipefail — grep returns exit 1 on no-match (normal),
# and pipefail would kill the script. Use explicit error checking throughout.

TOOL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load config
# shellcheck source=config/settings.conf
source "${TOOL_DIR}/config/settings.conf"

# Load secrets (gitignored, chmod 600) — created by menu option 8 or manually
if [[ -f "${TOOL_DIR}/config/secrets.conf" ]]; then
    source "${TOOL_DIR}/config/secrets.conf"
fi

# Load libraries
# shellcheck source=lib/utils.sh
source "${TOOL_DIR}/lib/utils.sh"
# shellcheck source=lib/repo-config.sh
source "${TOOL_DIR}/lib/repo-config.sh"
# shellcheck source=lib/checkout.sh
source "${TOOL_DIR}/lib/checkout.sh"
# shellcheck source=lib/analyze.sh
source "${TOOL_DIR}/lib/analyze.sh"
# shellcheck source=lib/copilot.sh
source "${TOOL_DIR}/lib/copilot.sh"
# shellcheck source=lib/report.sh
source "${TOOL_DIR}/lib/report.sh"
# shellcheck source=lib/instructions.sh
source "${TOOL_DIR}/lib/instructions.sh"
# shellcheck source=lib/jira-context.sh
source "${TOOL_DIR}/lib/jira-context.sh"

# Resolve REPO_PATH + GITHUB_REPO from the active repo in repos.conf
load_active_repo || true

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
preflight_checks() {
    require_command git
    require_command gh

    if [[ -z "${REPO_PATH:-}" || ! -d "$REPO_PATH" ]]; then
        print_error "Active repo '${ACTIVE_REPO}' not found at: ${REPO_PATH:-<not set>}"
        print_info "Use option 7 (Manage Repositories) to configure or switch repos."
        print_info "Continuing so you can access the menu and update the active repository."
    fi

    if ! gh auth status &>/dev/null; then
        print_error "GitHub CLI is not authenticated. Run: gh auth login"
        exit 1
    fi

    # ── Credential safety checks ─────────────────────────────────────────────
    local secrets_file="${TOOL_DIR}/config/secrets.conf"

    # Warn if secrets.conf is tracked by git (should never happen due to .gitignore)
    if git -C "$TOOL_DIR" ls-files --error-unmatch "$secrets_file" &>/dev/null 2>&1; then
        print_error "SECURITY: config/secrets.conf is tracked by git!"
        print_error "Your credentials may be exposed in git history."
        print_info  "Fix: git rm --cached config/secrets.conf && git commit -m 'remove secrets'"
    fi

    # Warn if secrets.conf permissions are too open
    if [[ -f "$secrets_file" ]]; then
        local perms
        perms=$(stat -c "%a" "$secrets_file" 2>/dev/null || stat -f "%A" "$secrets_file" 2>/dev/null)
        if [[ "$perms" != "600" && "$perms" != "400" ]]; then
            print_warn "config/secrets.conf permissions are ${perms} — should be 600."
            print_info "Fix: chmod 600 ${secrets_file}"
            chmod 600 "$secrets_file" && print_success "Auto-fixed permissions to 600."
        fi
    fi

    # Warn if any raw credentials exist in settings.conf
    if grep -qE '^JIRA_PAT="[^"$][^"]{3,}"' \
            "${TOOL_DIR}/config/settings.conf" 2>/dev/null; then
        print_error "SECURITY: JIRA_PAT found in config/settings.conf (git-tracked)!"
        print_info  "Move it to config/secrets.conf: run menu option 8 to reconfigure."
    fi

    ensure_dirs
}

# ---------------------------------------------------------------------------
# Display ASCII banner
# ---------------------------------------------------------------------------
show_banner() {
    echo -e "${BOLD}${CYAN}"
    echo "  ╔═══════════════════════════════════════════════════════════╗"
    echo "  ║          PAS  ·  PR Code Review Tool                      ║"
    printf "  ║          %-49s ║\n" "${GITHUB_REPO}"
    echo "  ╚═══════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
}

# ---------------------------------------------------------------------------
# Main menu
# ---------------------------------------------------------------------------
show_menu() {
    echo -e "${BOLD}  Active repo: ${CYAN}${ACTIVE_REPO}${RESET}${BOLD}  (${GITHUB_REPO})${RESET}\n"
    echo -e "  ${CYAN}1)${RESET} Review a Pull Request"
    echo -e "  ${CYAN}2)${RESET} View Review Rules"
    echo -e "  ${CYAN}3)${RESET} Edit Review Rules"
    echo -e "  ${CYAN}4)${RESET} Add a New Rule"
    echo -e "  ${CYAN}5)${RESET} View Past Reports"
    echo -e "  ${CYAN}6)${RESET} Clean Up PR Checkouts"
    echo -e "  ${CYAN}7)${RESET} Manage Repositories"
    echo -e "  ${CYAN}8)${RESET} Configure Jira Integration"
    echo -e "  ${CYAN}0)${RESET} Exit"
    echo ""
    printf "  \033[1m→\033[0m Enter choice [0-8]: "
    read -r MENU_CHOICE
}

# ---------------------------------------------------------------------------
# Workflow: Full PR Review pipeline
# ---------------------------------------------------------------------------
review_pr_workflow() {
    local pr_number="${1:-}"

    # Ask for PR number if not provided
    if [[ -z "$pr_number" ]]; then
        pr_number=$(prompt_input "Enter PR number to review" "")
        if [[ -z "$pr_number" || ! "$pr_number" =~ ^[0-9]+$ ]]; then
            print_error "Invalid PR number."
            return 1
        fi
    fi

    print_header "Reviewing PR #${pr_number}"

    # Step 1: Fetch PR metadata
    print_step "Fetching PR metadata from GitHub..."
    local metadata
    metadata=$(fetch_pr_metadata "$pr_number") || {
        print_error "Failed to fetch PR #${pr_number} metadata. Check the PR number and your gh auth."
        return 1
    }

    local pr_title pr_author pr_base pr_state pr_created
    pr_title=$(echo "$metadata"   | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['title'])" 2>/dev/null || echo "PR #${pr_number}")
    pr_author=$(echo "$metadata"  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['author'])" 2>/dev/null || echo "unknown")
    pr_base=$(echo "$metadata"    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['base'])" 2>/dev/null || echo "$DEFAULT_BASE_BRANCH")
    pr_state=$(echo "$metadata"   | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['state'])" 2>/dev/null || echo "unknown")
    pr_created=$(echo "$metadata" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['created_at'])" 2>/dev/null || echo "unknown")

    echo ""
    echo -e "  ${BOLD}Title:${RESET}   ${pr_title}"
    echo -e "  ${BOLD}Author:${RESET}  ${pr_author}"
    echo -e "  ${BOLD}Base:${RESET}    ${pr_base}"
    echo -e "  ${BOLD}State:${RESET}   ${pr_state}"
    echo ""

    # Step 2: Gather Jira story / defect context (optional)
    # NOTE: called directly (not via $(...)) so interactive prompts are visible
    JIRA_CONTEXT_RESULT=""
    gather_jira_context
    local jira_context="${JIRA_CONTEXT_RESULT:-}"

    # Step 3: Check for existing worktree BEFORE fetching
    # (git refuses to fetch into a branch checked out in a worktree)
    local worktree_path="${CHECKOUTS_DIR}/pr-${pr_number}"
    local reusing=false

    if [[ -d "$worktree_path" ]]; then
        print_warn "Checkout already exists: ${worktree_path}"
        if confirm_prompt "Re-use existing checkout (faster)?"; then
            reusing=true
            print_success "Re-using existing worktree"
        else
            remove_worktree "$pr_number"
        fi
    fi

    # Only fetch if we are NOT reusing an existing worktree
    if [[ "$reusing" == "false" ]]; then
        # Fully clean up any leftover worktree registration and branch before fetching.
        # This prevents "refusing to fetch into branch checked out at worktree" errors
        # that occur when a previous run left behind the branch (even without the directory).
        (cd "$REPO_PATH" && git worktree remove "${worktree_path}" --force 2>/dev/null) || true
        (cd "$REPO_PATH" && git worktree prune 2>/dev/null) || true
        (cd "$REPO_PATH" && git branch -D "pr-${pr_number}" 2>/dev/null) || true

        fetch_pr "$pr_number" || return 1
        worktree_path=$(create_worktree "$pr_number") || return 1
    fi

    # Step 4: Find merge base
    print_step "Determining merge base against origin/${pr_base}..."
    local merge_base
    merge_base=$(find_merge_base "$pr_number" "$pr_base") || {
        print_warn "Could not find merge base against origin/${pr_base}, trying origin/${DEFAULT_BASE_BRANCH}..."
        merge_base=$(find_merge_base "$pr_number" "$DEFAULT_BASE_BRANCH") || {
            print_error "Failed to find merge base. Cannot continue."
            return 1
        }
    }
    print_success "Merge base: ${merge_base}"

    # Show changed files
    print_step "Changed files in PR #${pr_number}:"
    local changed_files
    mapfile -t changed_files < <(list_all_changed_files "$pr_number" "$merge_base")
    printf "  ${DIM}%s${RESET}\n" "${changed_files[@]}"
    echo -e "  ${BOLD}Total: ${#changed_files[@]} files changed${RESET}"
    echo ""

    # Step 5: Run static analysis
    run_full_analysis "$worktree_path" "$pr_number" "$merge_base"

    # Print findings to terminal
    print_findings_terminal

    # Step 6: Copilot AI analysis
    local ai_section=""
    if confirm_prompt "Run GitHub Copilot AI analysis? (recommended, may take ~30s)"; then
        local report_path_prelim
        report_path_prelim=$(get_report_path "$pr_number")
        ai_section=$(generate_copilot_section \
            "$pr_number" "$merge_base" "$pr_title" "$pr_author" "$pr_base" \
            "$report_path_prelim" "$jira_context")
    else
        ai_section="> _AI analysis skipped. Run again and choose 'Yes' to include Copilot review._"
    fi

    # Step 7: Generate report
    print_step "Generating Markdown report..."
    local report_path
    report_path=$(generate_report \
        "$pr_number" "$pr_title" "$pr_author" "$pr_base" "$pr_created" \
        "$merge_base" "$ai_section" "$jira_context")

    print_report_summary "$report_path" "$pr_number"

    # Step 8: Open report
    if confirm_prompt "Open the report now?"; then
        if command -v xdg-open &>/dev/null; then
            xdg-open "$report_path" &>/dev/null &
        else
            "${EDITOR:-nano}" "$report_path"
        fi
    fi
}

# ---------------------------------------------------------------------------
# View past reports
# ---------------------------------------------------------------------------
view_past_reports() {
    print_header "Past Review Reports"

    if [[ ! -d "$REPORTS_DIR" ]] || [[ -z "$(ls -A "$REPORTS_DIR" 2>/dev/null)" ]]; then
        print_info "No reports found in: ${REPORTS_DIR}"
        return
    fi

    local reports=()
    mapfile -t reports < <(ls -t "${REPORTS_DIR}"/*.md 2>/dev/null)

    if [[ ${#reports[@]} -eq 0 ]]; then
        print_info "No .md reports found."
        return
    fi

    echo ""
    local i=1
    for r in "${reports[@]}"; do
        local fname
        fname=$(basename "$r")
        local size
        size=$(wc -l < "$r" 2>/dev/null || echo "?")
        printf "  ${CYAN}%2d)${RESET} %-45s  ${DIM}%s lines${RESET}\n" "$i" "$fname" "$size"
        (( i += 1 ))
    done
    echo ""

    local choice
    choice=$(prompt_input "Enter report number to open (or press Enter to skip)" "")
    if [[ -n "$choice" && "$choice" =~ ^[0-9]+$ ]]; then
        local idx=$(( choice - 1 ))
        if [[ $idx -ge 0 && $idx -lt ${#reports[@]} ]]; then
            "${EDITOR:-nano}" "${reports[$idx]}"
        else
            print_error "Invalid selection."
        fi
    fi
}

# ---------------------------------------------------------------------------
# Clean up old PR checkouts
# ---------------------------------------------------------------------------
cleanup_checkouts() {
    print_header "PR Checkout Cleanup"
    list_checkouts

    if [[ ! -d "$CHECKOUTS_DIR" ]] || [[ -z "$(ls -A "$CHECKOUTS_DIR" 2>/dev/null)" ]]; then
        return
    fi

    local pr_num
    pr_num=$(prompt_input "Enter PR number to remove (or 'all' to remove all, Enter to cancel)" "")

    if [[ -z "$pr_num" ]]; then
        print_info "Cancelled."
        return
    fi

    if [[ "$pr_num" == "all" ]]; then
        if confirm_prompt "Remove ALL PR checkouts? This cannot be undone."; then
            for dir in "$CHECKOUTS_DIR"/pr-*/; do
                [[ -d "$dir" ]] || continue
                local pn
                pn=$(basename "$dir" | sed 's/pr-//')
                remove_worktree "$pn"
            done
        fi
    else
        remove_worktree "$pr_num"
    fi
}

# ---------------------------------------------------------------------------
# Show help
# ---------------------------------------------------------------------------
show_help() {
    cat <<HELP
${BOLD}PAS PR Review Tool${RESET}

${BOLD}USAGE${RESET}
  ./pr-review.sh              Start interactive menu
  ./pr-review.sh --pr <N>     Directly review PR number N
  ./pr-review.sh --help       Show this help

${BOLD}MULTI-REPO CONFIGURATION${RESET}
  Repos registry : ${TOOL_DIR}/config/repos.conf
    Format       : alias|github_owner/repo|/local/clone/path
  Active repo    : set via ACTIVE_REPO in config/settings.conf
                   or interactively through menu option 7.

  Currently active: ${ACTIVE_REPO}  (${GITHUB_REPO})

${BOLD}OTHER SETTINGS${RESET}
  Edit: ${TOOL_DIR}/config/settings.conf
  - ACTIVE_REPO       Alias of the repo to operate on
  - INSTRUCTIONS_FILE Path to pr-review.instructions.md
  - REPORTS_DIR       Where reports are saved
  - CHECKOUTS_DIR     Where PR worktrees are created

${BOLD}WHAT IT DOES${RESET}
  1. Fetches the PR branch from GitHub (isolated git worktree)
  2. Optionally fetches Jira story/defect context (summary, ACs, attachments)
  3. Scans changed files against all rules in the instructions file
  4. Runs GitHub Copilot AI for deeper narrative analysis (Jira-aware if context provided)
  5. Generates a Markdown report with severity-grouped findings + Jira context section

  Option 7 — Manage Repositories:
    Add / remove / switch active repo (pas-ou, pas-4u, etc.)

  Option 8 — Configure Jira Integration:
    Set JIRA_BASE_URL, JIRA_USER_EMAIL, JIRA_TOKEN for automatic story/defect fetch

${BOLD}REQUIREMENTS${RESET}
  - git (2.5+)
  - gh (GitHub CLI, authenticated: gh auth login)
  - bash (4+)
  - python3 (for JSON parsing)

${BOLD}REPORTS${RESET}
  Saved to: ${REPORTS_DIR}
  Filename: pr-<N>-review-<date>.md
HELP
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
main() {
    # Handle flags
    case "${1:-}" in
        --help|-h)
            show_help
            exit 0
            ;;
        --pr)
            preflight_checks
            show_banner
            review_pr_workflow "${2:-}"
            exit 0
            ;;
    esac

    # Interactive mode
    preflight_checks
    show_banner

    while true; do
        show_menu
        case "$MENU_CHOICE" in
            1) review_pr_workflow "" ;;
            2) view_rules ;;
            3) edit_rules ;;
            4) add_rule ;;
            5) view_past_reports ;;
            6) cleanup_checkouts ;;
            7) configure_repos_menu ;;
            8) jira_setup_wizard ;;
            0|q|Q|exit|quit)
                echo -e "\n  ${DIM}Goodbye!${RESET}\n"
                exit 0
                ;;
            *)
                print_warn "Invalid choice '${MENU_CHOICE}'. Enter a number 0-8."
                ;;
        esac
        echo ""
        printf "  \033[2mPress Enter to return to menu...\033[0m"
        read -r
    done
}

main "$@"
