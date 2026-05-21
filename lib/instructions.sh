#!/usr/bin/env bash
# =============================================================================
#  instructions.sh — Manage review instructions / rule files
# =============================================================================

# ---------------------------------------------------------------------------
# Pretty-print the rules summary table from the instructions file
# ---------------------------------------------------------------------------
view_rules() {
    if [[ ! -f "$INSTRUCTIONS_FILE" ]]; then
        print_error "Instructions file not found: ${INSTRUCTIONS_FILE}"
        print_info "Run 'Add New Rule' to create it, or update settings.conf with the correct path."
        return 1
    fi

    print_header "Review Rules — $(basename "$INSTRUCTIONS_FILE")"

    # Print each rule table found in the file with color-coded severity
    local in_table=0
    while IFS= read -r line; do
        if echo "$line" | grep -qE '^\| Rule \|'; then
            in_table=1
        fi
        if [[ $in_table -eq 1 ]]; then
            if echo "$line" | grep -qE '^\|'; then
                # Color-code rows by severity
                if echo "$line" | grep -qi '| Blocker |'; then
                    echo -e "${RED}${line}${RESET}"
                elif echo "$line" | grep -qi '| Major |'; then
                    echo -e "${ORANGE}${line}${RESET}"
                elif echo "$line" | grep -qi '| Minor |'; then
                    echo -e "${YELLOW}${line}${RESET}"
                else
                    echo -e "${DIM}${line}${RESET}"
                fi
            else
                in_table=0
            fi
        fi
    done < "$INSTRUCTIONS_FILE"

    echo ""
    print_info "Full file: ${INSTRUCTIONS_FILE}"
    print_info "Rule count: $(grep -c '^\| [A-Z]*-[0-9]' "$INSTRUCTIONS_FILE" 2>/dev/null || echo '?')"
}

# ---------------------------------------------------------------------------
# Open the instructions file in the configured editor
# ---------------------------------------------------------------------------
edit_rules() {
    if [[ ! -f "$INSTRUCTIONS_FILE" ]]; then
        print_warn "Instructions file not found: ${INSTRUCTIONS_FILE}"
        if confirm_prompt "Create a new instructions file at this path?"; then
            create_blank_instructions_file "$INSTRUCTIONS_FILE"
        else
            return 1
        fi
    fi

    print_info "Opening in ${EDITOR}: ${INSTRUCTIONS_FILE}"
    "$EDITOR" "$INSTRUCTIONS_FILE"
    print_success "Saved."
}

# ---------------------------------------------------------------------------
# Interactive: Add a new rule to the instructions file
# ---------------------------------------------------------------------------
add_rule() {
    if [[ ! -f "$INSTRUCTIONS_FILE" ]]; then
        print_warn "Instructions file not found."
        if confirm_prompt "Create a new instructions file?"; then
            create_blank_instructions_file "$INSTRUCTIONS_FILE"
        else
            return 1
        fi
    fi

    print_header "Add New Review Rule"

    # Suggest next rule ID
    local last_id
    last_id=$(grep -oP '[A-Z]+-[0-9]+' "$INSTRUCTIONS_FILE" 2>/dev/null | sort -t'-' -k2 -n | tail -1)
    print_info "Last rule ID in file: ${last_id:-none}"

    local rule_id severity description pr_reference code_bad code_good

    rule_id=$(prompt_input "Rule ID (e.g., COMP-20, NAME-11)")
    if [[ -z "$rule_id" ]]; then
        print_error "Rule ID cannot be empty."
        return 1
    fi

    # Check for duplicate
    if grep -q "^| ${rule_id} |" "$INSTRUCTIONS_FILE" 2>/dev/null; then
        print_warn "Rule '${rule_id}' already exists in the file."
        if ! confirm_prompt "Add anyway as a new entry?"; then
            return 0
        fi
    fi

    echo ""
    echo -e "  Severity options: ${RED}Blocker${RESET} | ${ORANGE}Major${RESET} | ${YELLOW}Minor${RESET}"
    severity=$(prompt_input "Severity" "Major")
    description=$(prompt_input "Short description (one line)")
    pr_reference=$(prompt_input "PR reference (e.g., #900, or leave blank)")

    echo ""
    print_info "Paste a short BAD code example (press Enter twice when done):"
    code_bad=""
    while IFS= read -r code_line; do
        [[ -z "$code_line" ]] && break
        code_bad+="${code_line}"$'\n'
    done

    echo ""
    print_info "Paste a short GOOD code example (press Enter twice when done):"
    code_good=""
    while IFS= read -r code_line; do
        [[ -z "$code_line" ]] && break
        code_good+="${code_line}"$'\n'
    done

    # Determine category section to insert into
    local category
    category=$(echo "$rule_id" | grep -oP '^[A-Z]+')
    local section_header
    case "$category" in
        NAME)  section_header="Naming Convention Rules" ;;
        COMP)  section_header="Angular Component Rules" ;;
        SVC)   section_header="Service Rules" ;;
        TPL)   section_header="Template Rules" ;;
        RES)   section_header="Resource Rules" ;;
        CLEAN) section_header="Cleanup Rules" ;;
        KARMA) section_header="Karma Test Rules" ;;
        PW)    section_header="Playwright Test Rules" ;;
        CUC)   section_header="Cucumber Test Rules" ;;
        ARCH)  section_header="Logic & Architecture Rules" ;;
        *)     section_header="" ;;
    esac

    # Append new rule entry at end of file
    cat >> "$INSTRUCTIONS_FILE" <<RULE_ENTRY

---

### ${rule_id} Detail

> **Rule**: ${description}
>
> **Severity**: ${severity}$([ -n "$pr_reference" ] && echo " | **PR**: ${pr_reference}" || echo "")

$([ -n "$code_bad" ] && cat <<CODE
\`\`\`typescript
// BAD
${code_bad}
// GOOD
${code_good}
\`\`\`
CODE
)
RULE_ENTRY

    # Also add to the summary table if category section found
    if [[ -n "$section_header" ]]; then
        # Insert into the table by finding the section header and adding after last row
        local table_line
        table_line=$(grep -n "^| ${rule_id}" "$INSTRUCTIONS_FILE" 2>/dev/null | tail -1 | cut -d: -f1)
        if [[ -z "$table_line" ]]; then
            # Find the right table and append
            python3 - "$INSTRUCTIONS_FILE" "$rule_id" "$severity" "$description" <<'PY' 2>/dev/null || true
import re, sys
instructions_file, rule_id, severity, description = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

with open(instructions_file, "r") as f:
    content = f.read()

table_row = f"| {rule_id} | {severity} | {description} |"
category = rule_id.split("-")[0]
pattern = r"(\| " + category + r"-\d+ \|[^\n]+\n)(?=\| " + category + r"-|\n|\Z)"
matches = list(re.finditer(pattern, content))
if matches:
    last = matches[-1]
    content = content[:last.end()] + table_row + "\n" + content[last.end():]
    with open(instructions_file, "w") as f:
        f.write(content)
PY
        fi
    fi

    print_success "Rule '${rule_id}' added to: ${INSTRUCTIONS_FILE}"
}

# ---------------------------------------------------------------------------
# List all available instructions files
# ---------------------------------------------------------------------------
list_instruction_files() {
    print_header "Available Instructions Files"

    # Search common locations
    local locations=(
        "$INSTRUCTIONS_FILE"
        "${REPO_PATH}/.github/instructions/"
        "${REPO_PATH}/.github/"
        "${TOOL_DIR}/"
    )

    local found=0
    for loc in "${locations[@]}"; do
        if [[ -f "$loc" ]]; then
            local size
            size=$(wc -l < "$loc" 2>/dev/null || echo "?")
            local rules
            rules=$(grep -c '^\| [A-Z]*-[0-9]' "$loc" 2>/dev/null || echo "?")
            printf "  ${GREEN}✔${RESET}  %-60s  ${DIM}%s lines, %s rules${RESET}\n" "$loc" "$size" "$rules"
            (( found += 1 ))
        elif [[ -d "$loc" ]]; then
            while IFS= read -r -d '' f; do
                local size
                size=$(wc -l < "$f" 2>/dev/null || echo "?")
                printf "  ${GREEN}✔${RESET}  %-60s  ${DIM}%s lines${RESET}\n" "$f" "$size"
                (( found += 1 ))
            done < <(find "$loc" -name "*.instructions.md" -print0 2>/dev/null)
        fi
    done

    if [[ $found -eq 0 ]]; then
        print_warn "No instructions files found in common locations."
    fi
    echo ""

    if confirm_prompt "Switch the active instructions file?"; then
        local new_path
        new_path=$(prompt_input "Enter full path to the instructions file")
        if [[ -f "$new_path" ]]; then
            # Update settings.conf
            local _scfg
            _scfg="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../config/settings.conf"
            python3 - "$_scfg" "INSTRUCTIONS_FILE" "$new_path" <<'PY'
import sys, re
target_file, key, value = sys.argv[1], sys.argv[2], sys.argv[3]
safe_val = "'" + value.replace("'", "'\\''" ) + "'"
new_line = f"{key}={safe_val}"
with open(target_file, "r") as f:
    content = f.read()
pattern = rf"^{re.escape(key)}=.*$"
if re.search(pattern, content, re.MULTILINE):
    content = re.sub(pattern, new_line, content, flags=re.MULTILINE)
with open(target_file, "w") as f:
    f.write(content)
PY
            INSTRUCTIONS_FILE="$new_path"
            print_success "Active instructions file updated to: ${new_path}"
        else
            print_error "File not found: ${new_path}"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Create a blank instructions file with the standard template structure
# ---------------------------------------------------------------------------
create_blank_instructions_file() {
    local path="$1"
    mkdir -p "$(dirname "$path")"

    cat > "$path" <<'TEMPLATE'
---
applyTo:
  - "**/*.ts"
  - "**/*.html"
  - "**/*.spec.ts"
  - "**/*.json"
---

# Code Review Guidelines

This document defines the review rules for this repository.

---

## Naming Convention Rules — PR Review

| Rule | Severity | Violation |
|------|----------|-----------|
| NAME-01 | Major | Inconsistent or verbose variable/attribute names |
| NAME-02 | Minor | Boolean variable missing descriptive prefix (is, has, can, should) |

---

## Angular Component Rules — PR Review

| Rule | Severity | Violation |
|------|----------|-----------|
| COMP-06 | Blocker | Component subscribes to observables but does not implement OnDestroy |

---

## Cleanup Rules — PR Review

| Rule | Severity | Violation |
|------|----------|-----------|
| CLEAN-04 | Major | console.log statements left in production code |

---

## Summary Checklist

| Category | Rules | Key Points |
|---|---|---|
| **Naming** | NAME-01 to NAME-02 | Descriptive names, is prefix for booleans |
| **Components** | COMP-06 | Always clean up subscriptions |
| **Cleanup** | CLEAN-04 | Remove debug statements |
TEMPLATE

    print_success "Created new instructions file: ${path}"
}
