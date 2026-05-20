#!/usr/bin/env bash
# =============================================================================
#  jira-context.sh — Fetch Jira story / defect context directly from Jira API
#
#  Authentication: Personal Access Token (PAT) — Bearer header
#    Generate at: <jira-url>/secure/ViewProfile.jspa → Personal Access Tokens
#
#  Configuration (set in config/settings.conf / config/secrets.conf or via
#  menu option 8):
#    JIRA_BASE_URL      e.g. https://jira.yourcompany.com
#    JIRA_PAT           Personal Access Token  (stored in secrets.conf)
#    JIRA_API_VERSION   2 | 3  (default: 2)
#    JIRA_AC_FIELD      Custom field ID for Acceptance Criteria (optional)
# =============================================================================

# ---------------------------------------------------------------------------
# Internal: Return the Jira REST API version to use (default: 2)
# ---------------------------------------------------------------------------
_jira_api_version() {
    echo "${JIRA_API_VERSION:-2}"
}

# ---------------------------------------------------------------------------
# Internal: Persist a config value to the appropriate file
#   JIRA_PAT → config/secrets.conf (gitignored, chmod 600)
#   Others   → config/settings.conf
# ---------------------------------------------------------------------------
_jira_save_setting() {
    local key="$1" value="$2"
    local settings_file="${TOOL_DIR}/config/settings.conf"
    local secrets_file="${TOOL_DIR}/config/secrets.conf"

    local target_file
    case "$key" in
        JIRA_PAT)
            target_file="$secrets_file"
            if [[ ! -f "$secrets_file" ]]; then
                cp "${TOOL_DIR}/config/secrets.conf.example" "$secrets_file" 2>/dev/null \
                    || touch "$secrets_file"
            fi
            chmod 600 "$secrets_file"
            ;;
        *)
            target_file="$settings_file"
            ;;
    esac

    if grep -q "^${key}=" "$target_file" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=\"${value}\"|" "$target_file"
    else
        echo "" >> "$target_file"
        echo "${key}=\"${value}\"" >> "$target_file"
    fi
}

# ---------------------------------------------------------------------------
# Interactive setup wizard — collects Jira URL + PAT and tests the connection
# ---------------------------------------------------------------------------
jira_setup_wizard() {
    print_header "Jira Integration Setup"
    print_info "Configure your Jira connection so the review tool can fetch story/defect details."
    echo ""
    print_info "You need a Personal Access Token (PAT):"
    print_info "  → ${JIRA_BASE_URL:-<your-jira-url>}/secure/ViewProfile.jspa  → Personal Access Tokens"
    echo ""

    # ── Base URL ─────────────────────────────────────────────────────────────
    local base_url
    base_url=$(prompt_input "Jira URL (e.g. https://jira.yourcompany.com)" "${JIRA_BASE_URL:-}")
    if [[ -z "$base_url" ]]; then
        print_warn "Setup cancelled — no URL provided."
        return 1
    fi
    base_url="${base_url%/}"

    # ── PAT ──────────────────────────────────────────────────────────────────
    printf "  \033[1m→\033[0m Personal Access Token (input hidden): " >&2
    local pat
    read -rs pat
    echo "" >&2
    if [[ -z "$pat" ]]; then
        print_warn "Setup cancelled — no PAT provided."
        return 1
    fi

    # ── Optional settings ────────────────────────────────────────────────────
    local api_version ac_field
    api_version=$(prompt_input "Jira REST API version" "${JIRA_API_VERSION:-2}")
    ac_field=$(prompt_input "Acceptance Criteria custom field ID (optional, e.g. customfield_10028)" "${JIRA_AC_FIELD:-}")

    # ── Connectivity test ─────────────────────────────────────────────────────
    print_info "Testing Jira connection..."
    local test_response display_name
    test_response=$(curl -s --max-time 10 \
        -H "Authorization: Bearer ${pat}" \
        -H "Accept: application/json" \
        "${base_url}/rest/api/${api_version}/myself" 2>/dev/null) || true

    display_name=$(echo "$test_response" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); print(d.get('displayName') or d.get('name',''))" \
        2>/dev/null)

    if [[ -z "$display_name" ]]; then
        print_error "Connection test failed. Check your Jira URL and PAT."
        print_info  "Response: $(echo "$test_response" | head -c 200)"
        return 1
    fi

    print_success "Connected as: ${display_name}"

    # ── Persist ───────────────────────────────────────────────────────────────
    _jira_save_setting "JIRA_BASE_URL"    "$base_url"
    _jira_save_setting "JIRA_API_VERSION" "$api_version"
    _jira_save_setting "JIRA_PAT"         "$pat"
    [[ -n "$ac_field" ]] && _jira_save_setting "JIRA_AC_FIELD" "$ac_field"

    # Apply in current session
    JIRA_BASE_URL="$base_url"
    JIRA_API_VERSION="$api_version"
    JIRA_PAT="$pat"
    [[ -n "$ac_field" ]] && JIRA_AC_FIELD="$ac_field"

    print_success "Jira credentials saved."
    echo ""
}

# ---------------------------------------------------------------------------
# Core: fetch a Jira issue and return formatted context block
# Returns: formatted markdown context on stdout; exit 1 on failure
# ---------------------------------------------------------------------------
fetch_jira_issue() {
    local issue_key="$1"

    if [[ -z "${JIRA_BASE_URL:-}" || -z "${JIRA_PAT:-}" ]]; then
        return 1
    fi

    local api_version
    api_version=$(_jira_api_version)

    local fields="summary,description,issuetype,status,priority,labels,components,assignee,reporter,attachment"
    [[ -n "${JIRA_AC_FIELD:-}" ]] && fields+=",${JIRA_AC_FIELD}"
    fields+=",customfield_10028,customfield_10016,customfield_10014"

    print_info "Fetching ${issue_key} from Jira (API v${api_version})..." >&2
    start_spinner "Contacting Jira API..." >&2

    local response http_code
    response=$(curl -s --max-time 15 \
        -w "\n__HTTP_CODE__:%{http_code}" \
        -H "Authorization: Bearer ${JIRA_PAT}" \
        -H "Accept: application/json" \
        "${JIRA_BASE_URL}/rest/api/${api_version}/issue/${issue_key}?fields=${fields}" 2>/dev/null)
    stop_spinner >&2

    http_code=$(echo "$response" | grep -o '__HTTP_CODE__:[0-9]*' | cut -d: -f2)
    response=$(echo "$response" | sed 's/__HTTP_CODE__:[0-9]*$//')

    if [[ "$http_code" == "401" ]]; then
        print_error "Jira authentication failed (401). Check your JIRA_PAT — it may be expired or invalid." >&2
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
    # API v2 returns description as a plain string; API v3 returns ADF (dict)
    if isinstance(node, str):
        return node
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
# Main entry point: ensure credentials exist, ask for issue key, fetch & store
# result in global JIRA_CONTEXT_RESULT (call directly — do NOT use $(...))
# ---------------------------------------------------------------------------
gather_jira_context() {
    JIRA_CONTEXT_RESULT=""   # reset global output variable

    echo ""
    print_step "Jira Story / Defect Context"
    print_info "Fetch Jira details so Copilot can verify the PR matches its requirements."
    echo ""

    if ! confirm_prompt "Fetch Jira context for this review?" "n"; then
        return 0
    fi

    # First-time setup if not configured
    if [[ -z "${JIRA_BASE_URL:-}" || -z "${JIRA_PAT:-}" ]]; then
        print_warn "Jira not configured (JIRA_BASE_URL or JIRA_PAT missing)."
        if confirm_prompt "Run Jira setup wizard now?" "y"; then
            jira_setup_wizard || return 0
        else
            print_info "Tip: configure Jira via menu option 8 or set JIRA_* vars in config/secrets.conf"
            return 0
        fi
    fi

    local issue_key
    issue_key=$(prompt_input "Jira issue key (e.g. PAS-1234)")

    if [[ -z "$issue_key" ]]; then
        print_info "No issue key entered — skipping Jira context."
        return 0
    fi

    if [[ ! "$issue_key" =~ ^[A-Za-z][A-Za-z0-9]*-[0-9]+$ ]]; then
        print_warn "Key '${issue_key}' doesn't look like a valid Jira key (expected format: ABC-123)."
        if ! confirm_prompt "Continue anyway?" "n"; then
            return 0
        fi
    fi

    local context_text
    context_text=$(fetch_jira_issue "$issue_key") || {
        print_warn "Could not fetch Jira issue. The review will proceed without Jira context."
        return 0
    }

    print_success "Jira context loaded for ${issue_key} — included in AI review prompt."
    JIRA_CONTEXT_RESULT="$context_text"
}
