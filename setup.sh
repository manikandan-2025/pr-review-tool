#!/usr/bin/env bash
# =============================================================================
#  setup.sh — First-time setup for PR Review Tool
#
#  Run this once after cloning:
#    chmod +x setup.sh && ./setup.sh
#
#  What it does:
#    1. Checks for required tools (git, gh, python3)
#    2. Installs gh CLI if missing (Linux / macOS)
#    3. Logs you into GitHub (gh auth login)
#    4. Installs the GitHub Copilot CLI extension
#    5. Creates config/repos.conf from the example template
#    6. Creates config/secrets.conf (for Jira PAT — optional)
#    7. Installs the pre-commit security hook
#    8. Verifies the full setup and shows next steps
# =============================================================================

set -euo pipefail

TOOL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

ok()   { echo -e "  ${GREEN}✔${RESET}  $*"; }
info() { echo -e "  ${CYAN}ℹ${RESET}  $*"; }
warn() { echo -e "  ${YELLOW}⚠${RESET}  $*"; }
err()  { echo -e "  ${RED}✖${RESET}  $*" >&2; }
step() { echo -e "\n${BOLD}${CYAN}── $* ──${RESET}"; }
header() {
    echo ""
    echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}${CYAN}  $*${RESET}"
    echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════${RESET}"
}

ERRORS=0
fail() { err "$*"; (( ERRORS++ )) || true; }

# ── Step 1: Required base tools ───────────────────────────────────────────────
header "Step 1 — Checking required tools"

check_tool() {
    local cmd="$1" install_hint="$2"
    if command -v "$cmd" &>/dev/null; then
        ok "${cmd} found: $(command -v "$cmd")  ($(${cmd} --version 2>&1 | head -1))"
        return 0
    else
        warn "${cmd} not found."
        echo -e "         ${install_hint}"
        return 1
    fi
}

check_tool git  "Install: https://git-scm.com/downloads"
check_tool python3 "Install: https://www.python.org/downloads/"

# ── Step 2: GitHub CLI (gh) ───────────────────────────────────────────────────
header "Step 2 — GitHub CLI (gh)"

if command -v gh &>/dev/null; then
    ok "gh found: $(gh --version | head -1)"
else
    warn "gh CLI not found. Attempting to install..."
    echo ""

    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS — try brew
        if command -v brew &>/dev/null; then
            info "Installing via Homebrew..."
            brew install gh && ok "gh installed via Homebrew." || fail "brew install gh failed."
        else
            fail "Homebrew not found. Install manually:"
            echo "         https://cli.github.com/  or  brew install gh"
        fi
    elif [[ -f /etc/debian_version ]]; then
        # Debian / Ubuntu
        info "Installing via apt (requires sudo)..."
        (
            type -p curl >/dev/null || sudo apt-get install -y curl
            curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
                | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
            sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
https://cli.github.com/packages stable main" \
                | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
            sudo apt-get update -q && sudo apt-get install -y gh
        ) && ok "gh installed via apt." || fail "apt install failed. See: https://cli.github.com/"
    elif [[ -f /etc/redhat-release ]]; then
        # RHEL / Fedora / CentOS (supports both DNF4 and DNF5)
        info "Installing via dnf (requires sudo)..."
        sudo curl -fsSL https://cli.github.com/packages/rpm/gh-cli.repo \
            -o /etc/yum.repos.d/gh-cli.repo
        sudo dnf install -y gh && ok "gh installed via dnf." || fail "dnf install failed."
    else
        fail "Unknown OS. Install gh manually from: https://cli.github.com/"
    fi
fi

# ── Step 3: GitHub authentication ─────────────────────────────────────────────
header "Step 3 — GitHub authentication"

if gh auth status &>/dev/null 2>&1; then
    gh_user=$(gh auth status 2>&1 | grep "Logged in to github.com" | grep -o "account [^ ]*" | cut -d' ' -f2 || echo "unknown")
    ok "Already authenticated as: ${BOLD}${gh_user}${RESET}"
else
    warn "Not logged into GitHub."
    info "Launching interactive GitHub login..."
    echo ""
    if gh auth login; then
        ok "GitHub login successful."
    else
        fail "GitHub login failed or was cancelled."
        info "Run manually: gh auth login"
    fi
fi

# ── Step 4: Copilot CLI extension ─────────────────────────────────────────────
header "Step 4 — GitHub Copilot CLI extension"

if gh extension list 2>/dev/null | grep -q "gh-copilot\|copilot" || \
   gh copilot --version &>/dev/null 2>&1 || gh copilot -h &>/dev/null 2>&1; then
    ok "GitHub Copilot is available ($(gh copilot --version 2>/dev/null || echo 'built-in'))."
else
    warn "Copilot not found. Attempting to install as extension..."
    echo ""
    if gh extension install github/gh-copilot 2>&1; then
        ok "GitHub Copilot extension installed successfully."
    else
        fail "Could not install Copilot extension."
        info "Run manually: gh extension install github/gh-copilot"
        info "Docs: https://githubnext.com/projects/copilot-cli"
    fi
fi

# ── Step 5: repos.conf ────────────────────────────────────────────────────────
header "Step 5 — Repository configuration (repos.conf)"

REPOS_CONF="${TOOL_DIR}/config/repos.conf"
REPOS_EXAMPLE="${TOOL_DIR}/config/repos.conf.example"

if [[ -f "$REPOS_CONF" ]] && grep -qv "^#\|^$" "$REPOS_CONF" 2>/dev/null; then
    ok "repos.conf exists with entries:"
    grep -v "^#\|^$" "$REPOS_CONF" | while IFS='|' read -r alias gh_repo path; do
        echo -e "         ${BOLD}${alias}${RESET}  →  ${gh_repo}  (${path})"
    done
else
    if [[ ! -f "$REPOS_CONF" ]]; then
        cp "$REPOS_EXAMPLE" "$REPOS_CONF"
        info "Created config/repos.conf from example."
    fi
    echo ""
    warn "No repos configured yet. You need to add your local repository path."
    echo ""
    echo -e "  ${BOLD}Add your repo now?${RESET}"
    echo -e "  ${CYAN}1)${RESET} Yes — enter details now"
    echo -e "  ${CYAN}2)${RESET} Skip — I'll run ${BOLD}./pr-review.sh${RESET} → option 7 later"
    echo ""
    printf "  ${BOLD}→${RESET} Enter choice [1-2]: "
    read -r repo_choice

    if [[ "$repo_choice" == "1" ]]; then
        echo ""
        printf "  GitHub repo (owner/repo, e.g. myorg/myrepo): "
        read -r gh_repo
        printf "  Short alias (e.g. myrepo): "
        read -r alias
        printf "  Local clone path (e.g. ~/projects/myrepo): "
        read -r local_path
        # Expand ~
        local_path="${local_path/#\~/$HOME}"

        if [[ -n "$alias" && -n "$gh_repo" && -n "$local_path" ]]; then
            # Store with ~ if under $HOME for portability
            store_path="${local_path/$HOME/~}"
            echo "${alias}|${gh_repo}|${store_path}" >> "$REPOS_CONF"
            ok "Repo '${alias}' added to repos.conf"

            # Set as active repo in settings.local.conf (gitignored per-user file)
            LOCAL_SETTINGS="${TOOL_DIR}/config/settings.local.conf"
            if [[ -f "$LOCAL_SETTINGS" ]]; then
                sed -i "s|^ACTIVE_REPO=.*|ACTIVE_REPO=\"${alias}\"|" "$LOCAL_SETTINGS"
            else
                echo "ACTIVE_REPO=\"${alias}\"" > "$LOCAL_SETTINGS"
            fi
            ok "Active repo set to '${alias}' (saved to settings.local.conf)"

            if [[ ! -d "$local_path" ]]; then
                warn "Directory ${local_path} does not exist — clone it first:"
                info "  git clone https://github.com/${gh_repo} ${local_path}"
            fi
        else
            warn "Skipping — some fields were empty. Add via ./pr-review.sh → option 7."
        fi
    else
        info "Skipped. Run ./pr-review.sh → option 7 → Add a repo  when ready."
    fi
fi

# ── Step 6: secrets.conf (optional Jira PAT) ─────────────────────────────────
header "Step 6 — Jira credentials (optional)"

SECRETS_CONF="${TOOL_DIR}/config/secrets.conf"
SECRETS_EXAMPLE="${TOOL_DIR}/config/secrets.conf.example"

if [[ -f "$SECRETS_CONF" ]] && grep -q "JIRA_PAT=" "$SECRETS_CONF" && \
   ! grep -q 'JIRA_PAT=""' "$SECRETS_CONF" && ! grep -q "JIRA_PAT=your-" "$SECRETS_CONF"; then
    ok "secrets.conf exists with JIRA_PAT set."
    stat_perms=$(stat -c "%a" "$SECRETS_CONF" 2>/dev/null || stat -f "%Lp" "$SECRETS_CONF" 2>/dev/null)
    [[ "$stat_perms" == "600" ]] && ok "Permissions: 600 (secure)" \
                                  || warn "Permissions: ${stat_perms} — run: chmod 600 config/secrets.conf"
else
    info "Jira integration is optional. Skip if you don't use Jira."
    echo ""
    printf "  Set up Jira PAT now? [y/N]: "
    read -r jira_choice
    if [[ "$jira_choice" =~ ^[Yy]$ ]]; then
        [[ ! -f "$SECRETS_CONF" ]] && cp "$SECRETS_EXAMPLE" "$SECRETS_CONF"
        chmod 600 "$SECRETS_CONF"
        echo ""
        info "Your Jira PAT is a Personal Access Token from your Jira profile."
        info "Generate it at: https://id.atlassian.com/manage-profile/security/api-tokens"
        info "  (for Jira Server/DC: Profile → Personal Access Tokens)"
        echo ""
        printf "  Paste your Jira PAT (input hidden): "
        read -rs jira_pat
        echo ""
        if [[ -n "$jira_pat" ]]; then
            sed -i "s|^JIRA_PAT=.*|JIRA_PAT=\"${jira_pat}\"|" "$SECRETS_CONF"
            chmod 600 "$SECRETS_CONF"
            ok "JIRA_PAT saved to config/secrets.conf (permissions: 600)"
        else
            warn "No PAT entered. Run ./pr-review.sh → option 8 to set it later."
        fi
    else
        info "Skipped. Run ./pr-review.sh → option 8 to configure Jira later."
    fi
fi

# ── Step 7: Pre-commit security hook ─────────────────────────────────────────
header "Step 7 — Security hook"

HOOK="${TOOL_DIR}/.git/hooks/pre-commit"
if [[ -x "$HOOK" ]]; then
    ok "Pre-commit security hook already installed."
else
    info "Installing pre-commit hook (blocks accidental credential commits)..."
    mkdir -p "${TOOL_DIR}/.git/hooks"
    cat > "$HOOK" <<'HOOK_SCRIPT'
#!/usr/bin/env bash
# Pre-commit: block credential patterns and secrets.conf
patterns=('password\s*=' 'secret\s*=' 'api[_-]?key\s*=' 'token\s*=' 'JIRA_PAT\s*=')
for p in "${patterns[@]}"; do
    if git diff --cached -U0 | grep -qiE "$p"; then
        echo "✖  BLOCKED: Potential credential found matching pattern: $p"
        echo "   Remove it from staged changes before committing."
        exit 1
    fi
done
if git diff --cached --name-only | grep -q "config/secrets.conf"; then
    echo "✖  BLOCKED: config/secrets.conf must not be committed."
    exit 1
fi
HOOK_SCRIPT
    chmod +x "$HOOK"
    ok "Pre-commit hook installed."
fi

# ── Step 8: Final verification ────────────────────────────────────────────────
header "Step 8 — Verification"

checks_passed=0; checks_total=0

check() {
    local label="$1"; shift
    (( checks_total++ )) || true
    if "$@" &>/dev/null 2>&1; then
        ok "$label"
        (( checks_passed++ )) || true
    else
        warn "$label  ${YELLOW}(not ready)${RESET}"
    fi
}

check "git available"                command -v git
check "gh available"                 command -v gh
check "python3 available"            command -v python3
check "gh authenticated"             gh auth status
check "gh copilot available"         bash -c "gh copilot --version &>/dev/null 2>&1 || gh copilot -h &>/dev/null 2>&1 || gh extension list 2>/dev/null | grep -q copilot"
check "repos.conf exists"            test -f "${TOOL_DIR}/config/repos.conf"
check "repos.conf has entries"       bash -c "grep -qv '^#\|^$' '${TOOL_DIR}/config/repos.conf'"
check "secrets.conf exists"          test -f "${TOOL_DIR}/config/secrets.conf"
check "secrets.conf permissions"     bash -c "[[ \"\$(stat -c '%a' '${TOOL_DIR}/config/secrets.conf' 2>/dev/null || stat -f '%Lp' '${TOOL_DIR}/config/secrets.conf')\" == '600' ]]"
check "pre-commit hook installed"    test -x "${TOOL_DIR}/.git/hooks/pre-commit"
check "pr-review.sh executable"      test -x "${TOOL_DIR}/pr-review.sh"

echo ""
echo -e "  ${BOLD}${checks_passed}/${checks_total} checks passed${RESET}"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════${RESET}"
if [[ $ERRORS -eq 0 && $checks_passed -ge 9 ]]; then
    echo -e "${BOLD}${GREEN}  ✔  Setup complete! You're ready to use the PR Review Tool.${RESET}"
    echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════${RESET}"
    echo ""
    echo -e "  ${BOLD}Next steps:${RESET}"
    echo -e "  1. Run  ${BOLD}./pr-review.sh${RESET}"
    echo -e "  2. Choose option ${BOLD}1) Run Full PR Review${RESET} and enter a PR number"
    echo -e "  3. The tool generates a report in ${BOLD}./reports/${RESET}"
    echo ""
    echo -e "  ${CYAN}Need help?${RESET}  Read README.md or TEAM-GUIDE.md"
else
    echo -e "${BOLD}${YELLOW}  ⚠  Setup incomplete — ${ERRORS} error(s), ${checks_passed}/${checks_total} checks passed.${RESET}"
    echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════${RESET}"
    echo ""
    echo -e "  Fix the items marked ${YELLOW}⚠${RESET} above, then re-run ${BOLD}./setup.sh${RESET}"
    echo ""
    echo -e "  ${BOLD}Common fixes:${RESET}"
    echo -e "  • gh not installed   → https://cli.github.com/"
    echo -e "  • Not authenticated  → gh auth login"
    echo -e "  • No Copilot ext     → gh extension install github/gh-copilot"
    echo -e "  • No repos           → ./pr-review.sh → option 7 → Add a repo"
fi
echo ""
