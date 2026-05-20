#!/usr/bin/env bash
# =============================================================================
#  jira-context.sh — Fetch Jira story / defect context directly from Jira API
#
#  Fetches: summary, issue type, status, priority, description,
#           acceptance criteria (custom field or parsed from description),
#           and attachment manifest.
#
#  Supports two authentication modes:
#    cloud  — Atlassian Cloud: email + API token (Basic Auth)
#             API token: https://id.atlassian.com/manage-profile/security/api-tokens
#    pat    — Jira Data Center / Server: Personal Access Token (Bearer Auth)
#             PAT:       Jira → Profile → Personal Access Tokens
#
#  Configuration (set in config/settings.conf or via menu option 8):
#    JIRA_BASE_URL      e.g. https://yourcompany.atlassian.net  (Cloud)
#                       e.g. https://jira.yourcompany.com       (Server/DC)
#    JIRA_AUTH_TYPE     cloud | pat  (default: cloud)
#    JIRA_USER_EMAIL    Atlassian account email        (cloud mode only)
#    JIRA_TOKEN         Atlassian API token            (cloud mode only)
#    JIRA_PAT           Personal Access Token          (pat mode only)
#    JIRA_API_VERSION   2 | 3  (default: 3 for cloud, 2 for pat/DC)
#    JIRA_AC_FIELD      Custom field ID for Acceptance Criteria (optional)
# =============================================================================

# ---------------------------------------------------------------------------
# Internal: Return the curl auth flags for the current JIRA_AUTH_TYPE
# Usage: curl $(_jira_curl_auth) ...
# ---------------------------------------------------------------------------
_jira_curl_auth() {
    if [[ "${JIRA_AUTH_TYPE:-cloud}" == "pat" ]]; then
        echo "-H" "Authorization: Bearer ${JIRA_PAT}"
    else
        echo "-u" "${JIRA_USER_EMAIL}:${JIRA_TOKEN}"
    fi
}

# ---------------------------------------------------------------------------
# Internal: Return the configured (or default) Jira REST API version
# ---------------------------------------------------------------------------
_jira_api_version() {
    if [[ -n "${JIRA_API_VERSION:-}" ]]; then
        echo "$JIRA_API_VERSION"
    elif [[ "${JIRA_AUTH_TYPE:-cloud}" == "pat" ]]; then
        echo "2"   # Jira Data Center / Server default
    else
        echo "3"   # Atlassian Cloud default
    fi
}

# ---------------------------------------------------------------------------
# Internal: Persist a config value to settings.conf
# ---------------------------------------------------------------------------
_jira_save_setting() {
    local key="$1" value="$2"
    local settings_file="${TOOL_DIR}/config/settings.conf"

    if grep -q "^${key}=" "$settings_file" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=\"${value}\"|" "$settings_file"
    else
        echo "" >> "$settings_file"
        echo "${key}=\"${value}\"" >> "$settings_file"
    fi
}

# ---------------------------------------------------------------------------
# Interactive first-time setup wizard for Jira credentials
# Supports both Atlassian Cloud (email + API token) and
# Jira Data Center / Server (Personal Access Token)
# ---------------------------------------------------------------------------
jira_setup_wizard() {
    print_header "Jira Integration Setup"
    print_info "Configure your Jira connection so the review tool can fetch story/defect details."
    echo ""

    # ── Step 1: Auth type ────────────────────────────────────────────────────
    echo -e "  Authentication mode:"
    echo -e "  ${CYAN}1)${RESET} Cloud   — Atlassian Cloud  (email + API token)"
    echo -e "  ${CYAN}2)${RESET} PAT     — Jira Data Center / Server  (Personal Access Token)"
    echo ""
    printf "  \033[1m→\033[0m Select mode [1/2] (default: 1): "
    read -r auth_choice
    auth_choice="${auth_choice:-1}"

    local auth_type base_url
    case "$auth_choice" in
        2) auth_type="pat" ;;
        *) auth_type="cloud" ;;
    esac

    # ── Step 2: Base URL ─────────────────────────────────────────────────────
    if [[ "$auth_type" == "cloud" ]]; then
        base_url=$(prompt_input "Jira Cloud URL (e.g. https://yourcompany.atlassian.net)")
    else
        base_url=$(prompt_input "Jira Server/DC URL (e.g. https://jira.yourcompany.com)")
    fi

    if [[ -z "$base_url" ]]; then
        print_warn "Setup cancelled — no URL provided."
        return 1
    fi
    base_url="${base_url%/}"

    # ── Step 3: Credentials ──────────────────────────────────────────────────
    local email="" token="" pat=""

    if [[ "$auth_type" == "cloud" ]]; then
        print_info "Generate an API token at: https://id.atlassian.com/manage-profile/security/api-tokens"
        echo ""
        email=$(prompt_input "Atlassian account email")
        if [[ -z "$email" ]]; then
            print_warn "Setup cancelled — no email provided."
            return 1
        fi
        printf "  \033[1m→\033[0m API token (input hidden): " >&2
        read -rs token
        echo "" >&2
        if [[ -z "$token" ]]; then
            print_warn "Setup cancelled — no token provided."
            return 1
        fi
    else
        print_info "Generate a PAT at: ${base_url}/secure/ViewProfile.jspa → Personal Access Tokens"
        echo ""
        printf "  \033[1m→\033[0m Personal Access Token (input hidden): " >&2
        read -rs pat
        echo "" >&2
        if [[ -z "$pat" ]]; then
            print_warn "Setup cancelled — no PAT provided."
            return 1
        fi
    fi

    # ── Step 4: Optional settings ────────────────────────────────────────────
    local ac_field api_version
    ac_field=$(prompt_input "Acceptance Criteria custom field ID (optional, e.g. customfield_10028)" "")

    local default_api_version
    default_api_version=$( [[ "$auth_type" == "pat" ]] && echo "2" || echo "3" )
    api_version=$(prompt_input "Jira REST API version" "$default_api_version")

    # ── Step 5: Connectivity test ────────────────────────────────────────────
    print_info "Testing Jira connection..." >&2

    local test_response display_name
    if [[ "$auth_type" == "cloud" ]]; then
        test_response=$(curl -s --max-time 10 \
            -u "${email}:${token}" \
            -H "Accept: application/json" \
            "${base_url}/rest/api/${api_version}/myself" 2>/dev/null) || true
    else
        test_response=$(curl -s --max-time 10 \
            -H "Authorization: Bearer ${pat}" \
            -H "Accept: application/json" \
            "${base_url}/rest/api/${api_version}/myself" 2>/dev/null) || true
    fi

    display_name=$(echo "$test_response" | python3 -c \
        "import sys,json; print(json.load(sys.stdin).get('displayName') or json.load(open('/dev/stdin'))['name'])" \
        2>/dev/null || \
        echo "$test_response" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); print(d.get('displayName','') or d.get('name',''))" 2>/dev/null)

    if [[ -z "$display_name" ]]; then
        print_error "Connection test failed. Check your URL and credentials."
        print_info  "Response: $(echo "$test_response" | head -c 200)"
        return 1
    fi

    print_success "Connected as: ${display_name}"

    # ── Step 6: Persist ──────────────────────────────────────────────────────
    _jira_save_setting "JIRA_AUTH_TYPE"     "$auth_type"
    _jira_save_setting "JIRA_BASE_URL"      "$base_url"
    _jira_save_setting "JIRA_API_VERSION"   "$api_version"
    [[ -n "$ac_field" ]] && _jira_save_setting "JIRA_AC_FIELD" "$ac_field"

    if [[ "$auth_type" == "cloud" ]]; then
        _jira_save_setting "JIRA_USER_EMAIL" "$email"
        _jira_save_setting "JIRA_TOKEN"      "$token"
        # Apply in session
        JIRA_USER_EMAIL="$email"
        JIRA_TOKEN="$token"
    else
        _jira_save_setting "JIRA_PAT" "$pat"
        JIRA_PAT="$pat"
    fi

    JIRA_AUTH_TYPE="$auth_type"
    JIRA_BASE_URL="$base_url"
    JIRA_API_VERSION="$api_version"
    [[ -n "$ac_field" ]] && JIRA_AC_FIELD="$ac_field"

    print_success "Jira credentials saved to settings.conf."
    echo ""
}

# ---------------------------------------------------------------------------
# Core: fetch a Jira issue and return formatted context block
# Returns: formatted markdown context on stdout; exit 1 on failure
# ---------------------------------------------------------------------------
fetch_jira_issue() {
    local issue_key="$1"

    # Validate credentials are present for the configured auth type
    if [[ -z "${JIRA_BASE_URL:-}" ]]; then
        return 1
    fi
    if [[ "${JIRA_AUTH_TYPE:-cloud}" == "pat" ]]; then
        [[ -z "${JIRA_PAT:-}" ]] && return 1
    else
        [[ -z "${JIRA_USER_EMAIL:-}" || -z "${JIRA_TOKEN:-}" ]] && return 1
    fi

    local api_version
    api_version=$(_jira_api_version)

    # Build fields list — include common AC custom fields automatically
    local fields="summary,description,issuetype,status,priority,labels,components,assignee,reporter,attachment"
    [[ -n "${JIRA_AC_FIELD:-}" ]] && fields+=",${JIRA_AC_FIELD}"
    fields+=",customfield_10028,customfield_10016,customfield_10014"

    print_info "Fetching ${issue_key} from Jira (API v${api_version}, auth: ${JIRA_AUTH_TYPE:-cloud})..." >&2
    start_spinner "Contacting Jira API..." >&2

    local response http_code
    if [[ "${JIRA_AUTH_TYPE:-cloud}" == "pat" ]]; then
        response=$(curl -s --max-time 15 \
            -w "\n__HTTP_CODE__:%{http_code}" \
            -H "Authorization: Bearer ${JIRA_PAT}" \
            -H "Accept: application/json" \
            "${JIRA_BASE_URL}/rest/api/${api_version}/issue/${issue_key}?fields=${fields}" 2>/dev/null)
    else
        response=$(curl -s --max-time 15 \
            -w "\n__HTTP_CODE__:%{http_code}" \
            -u "${JIRA_USER_EMAIL}:${JIRA_TOKEN}" \
            -H "Accept: application/json" \
            "${JIRA_BASE_URL}/rest/api/${api_version}/issue/${issue_key}?fields=${fields}" 2>/dev/null)
    fi
    stop_spinner >&2

    http_code=$(echo "$response" | grep -o '__HTTP_CODE__:[0-9]*' | cut -d: -f2)
    response=$(echo "$response" | sed 's/__HTTP_CODE__:[0-9]*$//')

    if [[ "$http_code" == "401" ]]; then
        if [[ "${JIRA_AUTH_TYPE:-cloud}" == "pat" ]]; then
            print_error "Jira authentication failed (401). Check your JIRA_PAT — it may be expired or invalid." >&2
        else
            print_error "Jira authentication failed (401). Check JIRA_USER_EMAIL and JIRA_TOKEN." >&2
        fi
        return 1
    elif [[ "$http_code" == "404" ]]; then
        print_error "Issue '${issue_key}' not found in Jira (404). Check the issue key." >&2
        return 1
    elif [[ "$http_code" != "200" ]]; then
        print_error "Jira API error (HTTP ${http_code:-unknown})." >&2
        return 1
    fi

    # Parse and format the response with Python
    # Write JSON to a temp file so Python can read it from stdin while
    # the heredoc provides the script via process substitution
    local tmpjson
    tmpjson=$(mktemp /tmp/jira-XXXXXX.json)
    echo "$response" > "$tmpjson"

    python3 <(cat <<'PY'
import sys, json, re

issue_key  = sys.argv[1]
base_url   = sys.argv[2]
ac_field   = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] else ''
tmpjson    = sys.argv[4]

def adf_to_text(node, depth=0):
    if not isinstance(node, dict):
        return ''
    ntype = node.get('type', '')
    if ntype == 'text':
        text = node.get('text', '')
        marks = {m['type'] for m in node.get('marks', [])}
        if 'strong' in marks: text = f'**{text}**'
        if 'em' in marks:     text = f'_{text}_'
        return text
    children = [adf_to_text(c, depth+1) for c in node.get('content', [])]
    joined = ''.join(children)
    if ntype in ('paragraph','heading','bulletList','orderedList','listItem','blockquote','codeBlock'):
        return joined.rstrip() + '\n'
    return joined

def truncate(text, limit=1200):
    if len(text) <= limit:
        return text
    return text[:limit].rsplit('\n', 1)[0] + '\n…(truncated)'

def clean(text):
    return re.sub(r'\n{3,}', '\n\n', text).strip()

with open(tmpjson) as f:
    d = json.load(f)
fields = d.get('fields', {})

summary    = fields.get('summary', '(no summary)')
issuetype  = fields.get('issuetype', {}).get('name', 'Issue')
status     = fields.get('status', {}).get('name', 'Unknown')
priority   = (fields.get('priority') or {}).get('name', '')
labels     = ', '.join(fields.get('labels', []))
components = ', '.join(c['name'] for c in (fields.get('components') or []))
assignee   = (fields.get('assignee') or {}).get('displayName', 'Unassigned')

jira_url = f"{base_url}/browse/{issue_key}"

lines = []
lines.append(f"### 📋 Jira Context: [{issue_key}]({jira_url})")
lines.append(f"| Field | Value |")
lines.append(f"|---|---|")
lines.append(f"| **Type** | {issuetype} |")
lines.append(f"| **Status** | {status} |")
if priority:   lines.append(f"| **Priority** | {priority} |")
if assignee:   lines.append(f"| **Assignee** | {assignee} |")
if labels:     lines.append(f"| **Labels** | {labels} |")
if components: lines.append(f"| **Components** | {components} |")
lines.append(f"| **URL** | {jira_url} |")
lines.append("")
lines.append(f"**Summary:** {summary}")
lines.append("")

# --- Description ---
desc_raw = fields.get('description')
if desc_raw:
    desc = clean(adf_to_text(desc_raw))
    if desc:
        lines.append("**Description / Acceptance Criteria:**")
        lines.append(truncate(desc))
        lines.append("")

# --- Dedicated AC custom field ---
# Try user-specified field, then common defaults
for fid in [ac_field, 'customfield_10028', 'customfield_10016', 'customfield_10014']:
    if not fid:
        continue
    val = fields.get(fid)
    if not val:
        continue
    # Could be string, number, or ADF object
    if isinstance(val, dict) and 'content' in val:
        text = clean(adf_to_text(val))
        if text and text not in (clean(adf_to_text(desc_raw)) if desc_raw else ''):
            lines.append("**Acceptance Criteria:**")
            lines.append(truncate(text))
            lines.append("")
            break
    elif isinstance(val, str) and val.strip():
        if val.strip() not in (clean(adf_to_text(desc_raw)) if desc_raw else ''):
            lines.append("**Acceptance Criteria:**")
            lines.append(truncate(val.strip()))
            lines.append("")
            break

# --- Attachments ---
attachments = fields.get('attachment', [])
if attachments:
    lines.append(f"**Attachments ({len(attachments)}):**")
    for att in attachments[:10]:
        fname   = att.get('filename', 'unknown')
        mime    = att.get('mimeType', '')
        size_kb = round(att.get('size', 0) / 1024, 1)
        att_url = att.get('content', '')
        icon = '🖼️' if mime.startswith('image/') else ('📄' if 'pdf' in mime else '📎')
        lines.append(f"  {icon} [{fname}]({att_url}) `{size_kb} KB`")
    if len(attachments) > 10:
        lines.append(f"  …and {len(attachments) - 10} more")
    lines.append("")

print('\n'.join(lines))
PY
    ) "$issue_key" "${JIRA_BASE_URL}" "${JIRA_AC_FIELD:-}" "$tmpjson"
    local py_exit=$?
    rm -f "$tmpjson"
    return $py_exit
}

# ---------------------------------------------------------------------------
# Main entry point: ensure credentials exist, ask for issue key, fetch & return
# context as a formatted string (stdout).  All UI goes to stderr.
# ---------------------------------------------------------------------------
gather_jira_context() {
    echo "" >&2
    print_step "Jira Story / Defect Context" >&2
    print_info "Fetch Jira details so Copilot can verify the PR matches its requirements." >&2
    echo "" >&2

    if ! confirm_prompt "Fetch Jira context for this review?" "n"; then
        echo ""
        return 0
    fi

    # First-time setup if not configured
    local needs_setup=false
    if [[ -z "${JIRA_BASE_URL:-}" ]]; then
        needs_setup=true
    elif [[ "${JIRA_AUTH_TYPE:-cloud}" == "pat" && -z "${JIRA_PAT:-}" ]]; then
        needs_setup=true
    elif [[ "${JIRA_AUTH_TYPE:-cloud}" != "pat" && ( -z "${JIRA_USER_EMAIL:-}" || -z "${JIRA_TOKEN:-}" ) ]]; then
        needs_setup=true
    fi

    if [[ "$needs_setup" == "true" ]]; then
        print_warn "Jira credentials not configured." >&2
        if confirm_prompt "Run Jira setup wizard now?" "y"; then
            jira_setup_wizard || { echo ""; return 0; }
        else
            print_info "Tip: configure Jira via menu option 8 or set JIRA_* vars in config/settings.conf" >&2
            echo ""
            return 0
        fi
    fi

    local issue_key
    issue_key=$(prompt_input "Jira issue key (e.g. PAS-1234)")

    if [[ -z "$issue_key" ]]; then
        print_info "No issue key entered — skipping Jira context." >&2
        echo ""
        return 0
    fi

    if [[ ! "$issue_key" =~ ^[A-Za-z][A-Za-z0-9]*-[0-9]+$ ]]; then
        print_warn "Key '${issue_key}' doesn't look like a valid Jira key (expected format: ABC-123)." >&2
        if ! confirm_prompt "Continue anyway?" "n"; then
            echo ""
            return 0
        fi
    fi

    local context_text
    context_text=$(fetch_jira_issue "$issue_key") || {
        print_warn "Could not fetch Jira issue. The review will proceed without Jira context." >&2
        echo ""
        return 0
    }

    print_success "Jira context loaded for ${issue_key} — included in AI review prompt." >&2
    echo ""
    echo "$context_text"
}
