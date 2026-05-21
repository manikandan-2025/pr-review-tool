#!/usr/bin/env bash
# =============================================================================
#  utils.sh — Shared helpers: colors, logging, spinner, prompts
# =============================================================================

# ---------------------------------------------------------------------------
# ANSI Colors & Styles
# ---------------------------------------------------------------------------
RED='\033[0;31m'
ORANGE='\033[0;33m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

SEV_BLOCKER="${RED}${BOLD}🔴 BLOCKER${RESET}"
SEV_MAJOR="${ORANGE}${BOLD}🟠 MAJOR${RESET}"
SEV_MINOR="${YELLOW}${BOLD}🟡 MINOR${RESET}"
SEV_OK="${GREEN}${BOLD}✅ CLEAN${RESET}"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
print_header() {
    echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}${CYAN}  $*${RESET}"
    echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════${RESET}\n"
}

print_info()    { echo -e "  ${CYAN}ℹ${RESET}  $*"; }
print_success() { echo -e "  ${GREEN}✔${RESET}  $*"; }
print_warn()    { echo -e "  ${YELLOW}⚠${RESET}  $*"; }
print_error()   { echo -e "  ${RED}✖${RESET}  $*" >&2; }
print_step()    { echo -e "\n${BOLD}▶ $*${RESET}"; }
print_rule()    { echo -e "${DIM}──────────────────────────────────────────────────${RESET}"; }

# ---------------------------------------------------------------------------
# Spinner
# ---------------------------------------------------------------------------
_SPINNER_PID=""

start_spinner() {
    local msg="${1:-Working...}"
    local spin=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    (
        i=0
        while true; do
            printf "\r  ${CYAN}%s${RESET}  %s " "${spin[$i]}" "$msg" >&2
            i=$(( (i+1) % 10 ))
            sleep 0.1
        done
    ) &
    _SPINNER_PID=$!
    disown "$_SPINNER_PID" 2>/dev/null || true
}

stop_spinner() {
    if [[ -n "$_SPINNER_PID" ]]; then
        kill "$_SPINNER_PID" 2>/dev/null
        _SPINNER_PID=""
        printf "\r\033[K" >&2
    fi
}

# ---------------------------------------------------------------------------
# User prompts
# ---------------------------------------------------------------------------
confirm_prompt() {
    # confirm_prompt "Do the thing?" → returns 0 for yes, 1 for no
    local question="$1"
    local default="${2:-y}"  # y or n
    local prompt
    if [[ "$default" == "y" ]]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi
    while true; do
        printf "  \033[1m?\033[0m %s \033[2m%s\033[0m " "$question" "$prompt"
        read -r answer
        answer="${answer:-$default}"
        case "${answer,,}" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *)     print_warn "Please enter y or n." ;;
        esac
    done
}

prompt_input() {
    # prompt_input "Label" [default] → echoes trimmed input
    # printf goes to stderr so the prompt is visible even inside $() captures
    local label="$1"
    local default="${2:-}"
    local hint=""
    [[ -n "$default" ]] && hint=" (default: ${default})"
    printf "  \033[1m→\033[0m %s%s: " "$label" "$hint" >&2
    read -r value
    value="${value:-$default}"
    echo "$value"
}

# ---------------------------------------------------------------------------
# Misc helpers
# ---------------------------------------------------------------------------
require_command() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        print_error "Required command '${cmd}' not found. Please install it."
        exit 1
    fi
}

pad_right() {
    # pad_right "string" width → pads string to width with spaces
    printf "%-${2}s" "$1"
}

severity_badge() {
    case "${1^^}" in
        BLOCKER) echo -e "${SEV_BLOCKER}" ;;
        MAJOR)   echo -e "${SEV_MAJOR}" ;;
        MINOR)   echo -e "${SEV_MINOR}" ;;
        *)       echo -e "$1" ;;
    esac
}

severity_emoji() {
    case "${1^^}" in
        BLOCKER) echo "🔴" ;;
        MAJOR)   echo "🟠" ;;
        MINOR)   echo "🟡" ;;
        *)       echo "⚪" ;;
    esac
}

# Ensure required dirs exist
ensure_dirs() {
    install -d -m 700 "$REPORTS_DIR" "$CHECKOUTS_DIR"
}
