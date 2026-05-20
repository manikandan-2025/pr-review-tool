#!/usr/bin/env bash
# =============================================================================
#  copilot.sh — AI-powered review via GitHub Copilot CLI
#  Builds a structured prompt from the rules + PR diff, then invokes
#  `gh copilot explain` for narrative analysis.
#  Falls back to generating a paste-ready prompt file for VS Code Copilot.
# =============================================================================

# ---------------------------------------------------------------------------
# Build the review prompt (rules summary + file diffs)
# ---------------------------------------------------------------------------
build_review_prompt() {
    local pr_number="$1"
    local merge_base="$2"
    local pr_title="$3"
    local pr_author="$4"
    local pr_base="$5"
    local jira_context="${6:-}"

    local rules_summary
    rules_summary=$(extract_rules_summary)

    # Gather changed source files for diff
    local source_files
    mapfile -t source_files < <(list_changed_files "$pr_number" "$merge_base")

    local diff_content=""
    local files_included=0
    for f in "${source_files[@]}"; do
        # Limit diff size to avoid token limits — max 15 files
        [[ $files_included -ge 15 ]] && break
        local file_diff
        file_diff=$(get_file_diff "$pr_number" "$merge_base" "$f" 2>/dev/null)
        if [[ -n "$file_diff" ]]; then
            diff_content+="
### File: ${f}
\`\`\`diff
${file_diff}
\`\`\`
"
            (( files_included += 1 ))
        fi
    done

    local remaining=$(( ${#source_files[@]} - files_included ))
    local remaining_note=""
    [[ $remaining -gt 0 ]] && remaining_note="
> Note: ${remaining} additional files not shown due to size limits."

    cat <<PROMPT
You are a senior Angular developer performing a code review for the \`dedalus-cis4u/pas-ou\` repository.

## Pull Request Details
- **PR**: #${pr_number}
- **Title**: ${pr_title}
- **Author**: ${pr_author}
- **Base branch**: ${pr_base}
$(if [[ -n "$jira_context" ]]; then echo "
## User Story / Defect Context (from Jira)
The PR is expected to implement or fix the following Jira item.
Use this to verify the code changes match the stated requirements and acceptance criteria.

${jira_context}
"; fi)
## Review Rules
The team follows these rules (violations are labeled with their rule IDs):

${rules_summary}

## Changed Files Diff
${diff_content}${remaining_note}

## Your Task
1. Review the diff above against ALL rules listed
$(if [[ -n "$jira_context" ]]; then echo "2. Verify the implementation against the Jira story/defect context above — flag any missing requirements or unaddressed acceptance criteria"; else echo "2. Identify violations not caught by static analysis (logic issues, design problems, architecture concerns)"; fi)
3. Assess overall code quality, readability, and maintainability
4. Highlight any BLOCKER issues that must be fixed before merge
5. Provide specific, actionable feedback with file:line references where possible
6. End with a brief "Merge Readiness" verdict: APPROVED / NEEDS CHANGES / BLOCKED

Format your response in Markdown.
PROMPT
}

# ---------------------------------------------------------------------------
# Extract a concise rules summary from the instructions file
# ---------------------------------------------------------------------------
extract_rules_summary() {
    if [[ ! -f "$INSTRUCTIONS_FILE" ]]; then
        echo "_(Instructions file not found at: ${INSTRUCTIONS_FILE})_"
        return
    fi

    # Extract just the rule tables (lines with | Rule | pattern)
    awk '
        /^\| Rule \|/ { in_table=1 }
        in_table && /^\|/ { print }
        in_table && !/^\|/ && NF > 0 { in_table=0 }
    ' "$INSTRUCTIONS_FILE" 2>/dev/null | head -120
}

# ---------------------------------------------------------------------------
# Invoke Copilot CLI for AI narrative analysis
# ---------------------------------------------------------------------------
run_copilot_analysis() {
    local prompt="$1"
    local output_file="$2"

    print_step "Running GitHub Copilot AI analysis..." >&2

    # Write prompt to a temp file
    local prompt_file
    prompt_file=$(mktemp /tmp/pr-review-prompt-XXXXXX.md)
    echo "$prompt" > "$prompt_file"

    # Use gh copilot -p with the prompt passed directly
    local copilot_output
    local exit_code=0

    start_spinner "Asking Copilot to review the diff..."
    # --available-tools (no args) = no tools; --no-ask-user = fully non-interactive
    # Filter: remove token stats footer and tool-invocation log lines (●, │, └)
    copilot_output=$(timeout 120 gh copilot -p "$prompt" --available-tools --no-ask-user 2>&1 \
        | grep -v "^Changes\s*\|^Requests\s*\|^Tokens\s*" \
        | grep -v "^[[:space:]]*[●│└]") || exit_code=$?
    stop_spinner

    rm -f "$prompt_file"

    if [[ $exit_code -ne 0 || -z "$copilot_output" ]]; then
        print_warn "Copilot CLI did not return a response (exit code: ${exit_code})" >&2
        print_warn "A ready-to-paste prompt has been saved for manual use in VS Code Copilot." >&2
        save_manual_prompt "$prompt" "$output_file"
        echo "_Copilot CLI analysis not available. Use the prompt file for VS Code Copilot Chat._"
        return 1
    fi

    # Save raw Copilot output
    echo "$copilot_output" > "${output_file%.md}-copilot-raw.txt"
    print_success "Copilot analysis complete" >&2
    echo "$copilot_output"
}

# ---------------------------------------------------------------------------
# Save a ready-to-paste prompt for manual VS Code Copilot use
# ---------------------------------------------------------------------------
save_manual_prompt() {
    local prompt="$1"
    local report_path="$2"
    local prompt_file="${report_path%.md}-copilot-prompt.md"

    cat > "$prompt_file" <<EOF
<!-- ================================================================
     GitHub Copilot Chat — Manual Review Prompt
     Copy the content below into VS Code Copilot Chat (@workspace)
     or paste at: https://github.com/copilot
     ================================================================ -->

${prompt}
EOF
    print_info "Prompt saved to: ${prompt_file}" >&2
    echo "$prompt_file"
}

# ---------------------------------------------------------------------------
# Full Copilot pipeline: build prompt → run → return AI section text
# ---------------------------------------------------------------------------
generate_copilot_section() {
    local pr_number="$1"
    local merge_base="$2"
    local pr_title="$3"
    local pr_author="$4"
    local pr_base="$5"
    local report_path="$6"
    local jira_context="${7:-}"

    local prompt
    prompt=$(build_review_prompt "$pr_number" "$merge_base" "$pr_title" "$pr_author" "$pr_base" "$jira_context")

    # Always save the prompt regardless of CLI availability
    local prompt_file
    prompt_file=$(save_manual_prompt "$prompt" "$report_path")

    local ai_output
    ai_output=$(run_copilot_analysis "$prompt" "$report_path")
    local ai_exit=$?

    if [[ $ai_exit -eq 0 && -n "$ai_output" ]]; then
        echo "$ai_output"
    else
        cat <<EOF
> ⚠️ **Copilot CLI analysis was not available for this run.**
>
> A ready-to-paste prompt has been saved at:
> \`${prompt_file}\`
>
> **To get AI analysis:**
> 1. Open VS Code Copilot Chat
> 2. Paste the contents of the prompt file
> 3. Copy the response back into this section of the report

EOF
    fi
}
