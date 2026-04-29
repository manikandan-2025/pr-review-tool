#!/usr/bin/env bash
# =============================================================================
#  pr-review.sh — Interactive PR Code Review Tool for dedalus-cis4u/pas-ou
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

# Load libraries
# shellcheck source=lib/utils.sh
source "${TOOL_DIR}/lib/utils.sh"
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

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
preflight_checks() {
    require_command git
    require_command gh

    if [[ ! -d "$REPO_PATH" ]]; then
        print_error "Repository not found at: ${REPO_PATH}"
        print_info "Update REPO_PATH in: ${TOOL_DIR}/config/settings.conf"
        exit 1
    fi

    if ! gh auth status &>/dev/null; then
        print_error "GitHub CLI is not authenticated. Run: gh auth login"
        exit 1
    fi

    ensure_dirs
}

# ---------------------------------------------------------------------------
# Display ASCII banner
# ---------------------------------------------------------------------------
show_banner() {
    echo -e "${BOLD}${CYAN}"
    cat <<'BANNER'
  ╔═══════════════════════════════════════════════════════════╗
  ║          PAS-OU  ·  PR Code Review Tool                   ║
  ║          dedalus-cis4u/pas-ou                             ║
  ╚═══════════════════════════════════════════════════════════╝
BANNER
    echo -e "${RESET}"
}

# ---------------------------------------------------------------------------
# Main menu
# ---------------------------------------------------------------------------
show_menu() {
    echo -e "${BOLD}  What would you like to do?${RESET}\n"
    echo -e "  ${CYAN}1)${RESET} Review a Pull Request"
    echo -e "  ${CYAN}2)${RESET} View Review Rules"
    echo -e "  ${CYAN}3)${RESET} Edit Review Rules"
    echo -e "  ${CYAN}4)${RESET} Add a New Rule"
    echo -e "  ${CYAN}5)${RESET} View Past Reports"
    echo -e "  ${CYAN}6)${RESET} Clean Up PR Checkouts"
    echo -e "  ${CYAN}7)${RESET} Post Report to GitHub PR"
    echo -e "  ${CYAN}8)${RESET} Exit"
    echo ""
    printf "  \033[1m→\033[0m Enter choice [1-8]: "
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

    # Step 2: Check for existing worktree BEFORE fetching
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
            "$report_path_prelim")
    else
        ai_section="> _AI analysis skipped. Run again and choose 'Yes' to include Copilot review._"
    fi

    # Step 7: Generate report
    print_step "Generating Markdown report..."
    local report_path
    report_path=$(generate_report \
        "$pr_number" "$pr_title" "$pr_author" "$pr_base" "$pr_created" \
        "$merge_base" "$ai_section")

    print_report_summary "$report_path" "$pr_number"

    # Step 8: Optional — post to GitHub
    if confirm_prompt "Post this report as a comment on PR #${pr_number}?"; then
        post_report_to_github "$pr_number" "$report_path"
    fi

    # Step 9: Open report
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
# Post report as GitHub PR comment
# ---------------------------------------------------------------------------
post_report_to_github() {
    local pr_number="$1"
    local report_path="$2"

    if [[ ! -f "$report_path" ]]; then
        print_error "Report file not found: ${report_path}"
        return 1
    fi

    print_step "Posting report to PR #${pr_number}..."
    start_spinner "Posting comment..."
    gh pr comment "$pr_number" \
        --repo "$GITHUB_REPO" \
        --body-file "$report_path" 2>&1
    local exit_code=$?
    stop_spinner

    if [[ $exit_code -eq 0 ]]; then
        print_success "Report posted to: https://github.com/${GITHUB_REPO}/pull/${pr_number}"
    else
        print_error "Failed to post comment. Check your gh auth permissions."
    fi
}

# ---------------------------------------------------------------------------
# Post report (standalone menu option — asks for PR number + report path)
# ---------------------------------------------------------------------------
post_report_menu() {
    print_header "Post Report to GitHub"

    local pr_num
    pr_num=$(prompt_input "PR number")
    [[ -z "$pr_num" ]] && return

    if [[ ! -d "$REPORTS_DIR" ]]; then
        print_error "No reports directory found: ${REPORTS_DIR}"
        return
    fi

    # Find matching report
    local matching_reports=()
    mapfile -t matching_reports < <(ls -t "${REPORTS_DIR}/pr-${pr_num}-"*.md 2>/dev/null)

    if [[ ${#matching_reports[@]} -eq 0 ]]; then
        print_warn "No reports found for PR #${pr_num}"
        local manual_path
        manual_path=$(prompt_input "Enter full path to report file manually" "")
        [[ -n "$manual_path" ]] && matching_reports=("$manual_path")
    fi

    if [[ ${#matching_reports[@]} -gt 1 ]]; then
        print_info "Multiple reports found:"
        local i=1
        for r in "${matching_reports[@]}"; do
            printf "  ${CYAN}%d)${RESET} %s\n" "$i" "$(basename "$r")"
            (( i += 1 ))
        done
        local choice
        choice=$(prompt_input "Select report number" "1")
        local idx=$(( choice - 1 ))
        post_report_to_github "$pr_num" "${matching_reports[$idx]}"
    elif [[ ${#matching_reports[@]} -eq 1 ]]; then
        post_report_to_github "$pr_num" "${matching_reports[0]}"
    fi
}

# ---------------------------------------------------------------------------
# Show help
# ---------------------------------------------------------------------------
show_help() {
    cat <<HELP
${BOLD}PAS-OU PR Review Tool${RESET}

${BOLD}USAGE${RESET}
  ./pr-review.sh              Start interactive menu
  ./pr-review.sh --pr <N>     Directly review PR number N
  ./pr-review.sh --help       Show this help

${BOLD}CONFIGURATION${RESET}
  Edit: ${TOOL_DIR}/config/settings.conf
  - REPO_PATH         Path to your local pas-ou clone
  - INSTRUCTIONS_FILE Path to pr-review.instructions.md
  - REPORTS_DIR       Where reports are saved
  - CHECKOUTS_DIR     Where PR worktrees are created

${BOLD}WHAT IT DOES${RESET}
  1. Fetches the PR branch from GitHub (isolated git worktree)
  2. Scans changed files against all rules in the instructions file
  3. Runs GitHub Copilot AI for deeper narrative analysis
  4. Generates a Markdown report with severity-grouped findings
  5. Optionally posts the report as a PR comment

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
            7) post_report_menu ;;
            8|q|Q|exit|quit)
                echo -e "\n  ${DIM}Goodbye!${RESET}\n"
                exit 0
                ;;
            *)
                print_warn "Invalid choice '${MENU_CHOICE}'. Enter a number 1-8."
                ;;
        esac
        echo ""
        printf "  \033[2mPress Enter to return to menu...\033[0m"
        read -r
    done
}

main "$@"
