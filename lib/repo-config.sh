#!/usr/bin/env bash
# =============================================================================
#  repo-config.sh — Multi-repo management
#
#  Reads config/repos.conf (alias|github_repo|local_path per line) and
#  exposes helpers to load, list, switch, add and remove repos.
#
#  Every entry stored as:   alias|github_owner/repo|/abs/local/path
# =============================================================================

# ---------------------------------------------------------------------------
# Internal: read repos.conf → populate parallel arrays
#   _REPO_ALIASES[]  _REPO_GH[]  _REPO_PATHS[]
# ---------------------------------------------------------------------------
_is_valid_repo_alias() {
    [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]
}

_load_repos_file() {
    _REPO_ALIASES=()
    _REPO_GH=()
    _REPO_PATHS=()

    if [[ ! -f "$REPOS_FILE" ]]; then
        print_warn "repos.conf not found at: ${REPOS_FILE}"
        return 1
    fi

    local line line_no=0 alias gh_repo local_path extra
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_no++))

        # Skip comments and blank lines
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        IFS='|' read -r alias gh_repo local_path extra <<< "$line"
        if [[ -z "$alias" || -z "$gh_repo" || -z "$local_path" || -n "$extra" ]]; then
            print_warn "Skipping invalid repos.conf entry at line ${line_no}: '${line}' (expected alias|github-owner/repo-name|/abs/path)"
            continue
        fi
        if ! _is_valid_repo_alias "$alias"; then
            print_warn "Skipping invalid alias at line ${line_no}: '${alias}' (allowed: letters, numbers, dot, underscore, hyphen)"
            continue
        fi

        _REPO_ALIASES+=("$alias")
        _REPO_GH+=("$gh_repo")
        _REPO_PATHS+=("$local_path")
    done < "$REPOS_FILE"
}

# ---------------------------------------------------------------------------
# load_active_repo — sets REPO_PATH and GITHUB_REPO from ACTIVE_REPO
# Called once at startup (after all libs are sourced).
# ---------------------------------------------------------------------------
load_active_repo() {
    _load_repos_file

    local i
    for i in "${!_REPO_ALIASES[@]}"; do
        if [[ "${_REPO_ALIASES[$i]}" == "$ACTIVE_REPO" ]]; then
            REPO_PATH="${_REPO_PATHS[$i]}"
            GITHUB_REPO="${_REPO_GH[$i]}"
            return 0
        fi
    done

    # Fallback: if ACTIVE_REPO is not found, use the first entry
    if [[ ${#_REPO_ALIASES[@]} -gt 0 ]]; then
        print_warn "Active repo '${ACTIVE_REPO}' not found in repos.conf — using '${_REPO_ALIASES[0]}'"
        ACTIVE_REPO="${_REPO_ALIASES[0]}"
        REPO_PATH="${_REPO_PATHS[0]}"
        GITHUB_REPO="${_REPO_GH[0]}"
        return 0
    fi

    print_error "repos.conf is empty. Add repos via menu option 7."
    return 1
}

# ---------------------------------------------------------------------------
# list_repos — print all repos, mark the active one
# ---------------------------------------------------------------------------
list_repos() {
    _load_repos_file

    if [[ ${#_REPO_ALIASES[@]} -eq 0 ]]; then
        print_info "No repos configured. Add one via option 7 → Add Repo."
        return
    fi

    echo ""
    printf "  ${BOLD}%-4s  %-12s  %-35s  %s${RESET}\n" "#" "Alias" "GitHub repo" "Local path"
    print_rule
    local i
    for i in "${!_REPO_ALIASES[@]}"; do
        local marker="  "
        [[ "${_REPO_ALIASES[$i]}" == "$ACTIVE_REPO" ]] && marker="${GREEN}▶${RESET} "
        local path_display="${_REPO_PATHS[$i]}"
        local exists_mark=""
        [[ ! -d "${_REPO_PATHS[$i]}" ]] && exists_mark=" ${RED}(path not found)${RESET}"
        printf "  %b%-2d)  %-12s  %-35s  %s%b\n" \
            "$marker" "$(( i + 1 ))" "${_REPO_ALIASES[$i]}" "${_REPO_GH[$i]}" \
            "$path_display" "$exists_mark"
    done
    echo ""
}

# ---------------------------------------------------------------------------
# switch_repo — interactively pick a new active repo, persist to settings.conf
# ---------------------------------------------------------------------------
switch_repo() {
    print_header "Switch Active Repository"
    list_repos

    local choice
    choice=$(prompt_input "Enter number or alias to switch to (Enter to cancel)" "")
    [[ -z "$choice" ]] && { print_info "Cancelled."; return 0; }

    _load_repos_file
    local idx=-1

    if [[ "$choice" =~ ^[0-9]+$ ]]; then
        # Numeric selection
        idx=$(( choice - 1 ))
        if [[ $idx -lt 0 || $idx -ge ${#_REPO_ALIASES[@]} ]]; then
            print_error "Selection out of range."; return 1
        fi
    else
        # Alias name selection
        local i
        for i in "${!_REPO_ALIASES[@]}"; do
            if [[ "${_REPO_ALIASES[$i]}" == "$choice" ]]; then
                idx=$i
                break
            fi
        done
        if [[ $idx -eq -1 ]]; then
            print_error "Unknown alias '${choice}'. Use a number or an exact alias from the list above."
            return 1
        fi
    fi

    local new_alias="${_REPO_ALIASES[$idx]}"
    if [[ "$new_alias" == "$ACTIVE_REPO" ]]; then
        print_info "Already on '${new_alias}'."
        return 0
    fi

    # Update settings.conf
    local conf="${TOOL_DIR}/config/settings.conf"
    sed -i "s|^ACTIVE_REPO=.*|ACTIVE_REPO=\"${new_alias}\"|" "$conf"
    ACTIVE_REPO="$new_alias"
    REPO_PATH="${_REPO_PATHS[$idx]}"
    GITHUB_REPO="${_REPO_GH[$idx]}"

    print_success "Switched to: ${BOLD}${new_alias}${RESET}  (${GITHUB_REPO})"
    if [[ ! -d "$REPO_PATH" ]]; then
        print_warn "Local path not found: ${REPO_PATH}"
        print_info "Clone the repo or update the path via 'Add / Edit Repo'."
    fi
}

# ---------------------------------------------------------------------------
# add_repo — prompt for alias/gh_repo/path and append to repos.conf
# ---------------------------------------------------------------------------
add_repo() {
    print_header "Add Repository"

    local repo_alias gh_repo local_path

    repo_alias=$(prompt_input "Short alias (e.g. pas-4u)" "")
    if [[ -z "$repo_alias" ]]; then print_info "Cancelled."; return 0; fi
    if ! _is_valid_repo_alias "$repo_alias"; then
        print_error "Invalid alias '${repo_alias}'. Use only letters, numbers, dot (.), underscore (_) and hyphen (-)."
        return 1
    fi

    # Check for duplicate alias
    _load_repos_file
    local a; for a in "${_REPO_ALIASES[@]}"; do
        if [[ "$a" == "$repo_alias" ]]; then
            print_error "Alias '${repo_alias}' already exists. Remove it first or choose a different name."
            return 1
        fi
    done

    gh_repo=$(prompt_input "GitHub repo (owner/repo)" "")
    if [[ -z "$gh_repo" ]]; then print_info "Cancelled."; return 0; fi

    local_path=$(prompt_input "Absolute local clone path" "")
    if [[ -z "$local_path" ]]; then print_info "Cancelled."; return 0; fi

    if [[ ! -d "$local_path" ]]; then
        print_warn "Directory does not exist: ${local_path}"
        confirm_prompt "Add it anyway?" || return 0
    fi

    echo "${repo_alias}|${gh_repo}|${local_path}" >> "$REPOS_FILE"
    print_success "Repo '${repo_alias}' added to repos.conf"

    if confirm_prompt "Switch to '${repo_alias}' now?"; then
        local conf="${TOOL_DIR}/config/settings.conf"
        sed -i "s|^ACTIVE_REPO=.*|ACTIVE_REPO=\"${repo_alias}\"|" "$conf"
        ACTIVE_REPO="$repo_alias"
        REPO_PATH="$local_path"
        GITHUB_REPO="$gh_repo"
        print_success "Active repo switched to: ${repo_alias}"
    fi
}

# ---------------------------------------------------------------------------
# remove_repo — remove an entry from repos.conf
# ---------------------------------------------------------------------------
remove_repo() {
    print_header "Remove Repository"
    list_repos

    _load_repos_file
    if [[ ${#_REPO_ALIASES[@]} -eq 0 ]]; then return; fi

    local choice
    choice=$(prompt_input "Enter number to remove (Enter to cancel)" "")
    [[ -z "$choice" ]] && { print_info "Cancelled."; return 0; }

    if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
        print_error "Invalid input."; return 1
    fi

    local idx=$(( choice - 1 ))
    if [[ $idx -lt 0 || $idx -ge ${#_REPO_ALIASES[@]} ]]; then
        print_error "Selection out of range."; return 1
    fi

    local alias_to_remove="${_REPO_ALIASES[$idx]}"

    if ! confirm_prompt "Remove '${alias_to_remove}'?"; then
        print_info "Cancelled."; return 0
    fi

    # Remove matching line from repos.conf (exact alias match at start of line)
    local escaped
    escaped=$(printf '%s\n' "$alias_to_remove" | sed 's/[[\.*^$()+?{|]/\\&/g')
    sed -i "/^${escaped}|/d" "$REPOS_FILE"
    print_success "Removed '${alias_to_remove}' from repos.conf"

    # If we just removed the active repo, switch to first remaining
    if [[ "$alias_to_remove" == "$ACTIVE_REPO" ]]; then
        _load_repos_file
        if [[ ${#_REPO_ALIASES[@]} -gt 0 ]]; then
            local conf="${TOOL_DIR}/config/settings.conf"
            sed -i "s|^ACTIVE_REPO=.*|ACTIVE_REPO=\"${_REPO_ALIASES[0]}\"|" "$conf"
            ACTIVE_REPO="${_REPO_ALIASES[0]}"
            REPO_PATH="${_REPO_PATHS[0]}"
            GITHUB_REPO="${_REPO_GH[0]}"
            print_warn "Active repo changed to: ${ACTIVE_REPO}"
        else
            print_warn "No repos left. Add one before using the review tool."
        fi
    fi
}

# ---------------------------------------------------------------------------
# configure_repos_menu — sub-menu for full repo management
# ---------------------------------------------------------------------------
configure_repos_menu() {
    while true; do
        print_header "Manage Repositories  [active: ${BOLD}${ACTIVE_REPO}${RESET}${CYAN}]"
        list_repos

        echo -e "  ${CYAN}1)${RESET} Switch active repo"
        echo -e "  ${CYAN}2)${RESET} Add a repo"
        echo -e "  ${CYAN}3)${RESET} Remove a repo"
        echo -e "  ${CYAN}4)${RESET} Back to main menu"
        echo ""
        printf "  ${BOLD}→${RESET} Enter choice [1-4]: "
        read -r repo_choice

        case "$repo_choice" in
            1) switch_repo ;;
            2) add_repo ;;
            3) remove_repo ;;
            4|q|Q|"") return 0 ;;
            *) print_warn "Invalid choice." ;;
        esac
        echo ""
        printf "  \033[2mPress Enter to continue...\033[0m"
        read -r
    done
}
