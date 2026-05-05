#!/usr/bin/env bash
# =============================================================================
#  copilot.sh — AI-powered review via GitHub Copilot CLI
#  Builds a structured prompt from the rules + PR diff, then invokes
#  `gh copilot -p` for narrative analysis.
#  Large PRs are split into chunks (COPILOT_CHUNK_SIZE) with one call each.
#  Falls back to generating a paste-ready prompt file for VS Code Copilot.
# =============================================================================

# ---------------------------------------------------------------------------
# Build a review prompt for a specific list of files (one chunk)
# ---------------------------------------------------------------------------
build_review_prompt() {
    local pr_number="$1"
    local merge_base="$2"
    local pr_title="$3"
    local pr_author="$4"
    local pr_base="$5"
    local chunk_num="$6"       # e.g. 1
    local total_chunks="$7"    # e.g. 3
    shift 7
    local files=("$@")

    local rules_summary
    rules_summary=$(extract_rules_summary)

    local diff_content=""
    local files_included=0
    for f in "${files[@]}"; do
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

    local chunk_context=""
    if [[ $total_chunks -gt 1 ]]; then
        chunk_context="
> **Note:** This PR has ${total_chunks} review chunks. This is chunk ${chunk_num} of ${total_chunks}.
> Focus only on the files listed below. A separate call covers the remaining files."
    fi

    cat <<PROMPT
You are a senior Angular developer performing a code review for the \`dedalus-cis4u/pas-ou\` repository.

## Pull Request Details
- **PR**: #${pr_number}
- **Title**: ${pr_title}
- **Author**: ${pr_author}
- **Base branch**: ${pr_base}
${chunk_context}

## Review Rules
The team follows these rules (violations are labeled with their rule IDs):

${rules_summary}

## Changed Files Diff (${files_included} file(s))
${diff_content}

## Your Task
1. Review the diff above against ALL rules listed
2. Identify violations not caught by static analysis (logic issues, design problems, architecture concerns)
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
# Invoke Copilot CLI for one prompt — returns output on stdout
# ---------------------------------------------------------------------------
run_copilot_analysis() {
    local prompt="$1"
    local output_file="$2"
    local chunk_label="${3:-}"    # e.g. "chunk 1/3" for display

    local spinner_msg="Asking Copilot to review the diff..."
    [[ -n "$chunk_label" ]] && spinner_msg="Asking Copilot (${chunk_label})..."

    local copilot_output
    local exit_code=0

    start_spinner "$spinner_msg"
    # --available-tools (no args) = no tools; --no-ask-user = fully non-interactive
    # Filter: remove token stats footer and tool-invocation log lines (●, │, └)
    copilot_output=$(timeout "${COPILOT_TIMEOUT:-180}" gh copilot -p "$prompt" \
        --available-tools --no-ask-user 2>&1 \
        | grep -v "^Changes\s*\|^Requests\s*\|^Tokens\s*" \
        | grep -v "^[[:space:]]*[●│└]") || exit_code=$?
    stop_spinner

    if [[ $exit_code -ne 0 || -z "$copilot_output" ]]; then
        print_warn "Copilot did not return a response for ${chunk_label:-this chunk} (exit: ${exit_code})" >&2
        return 1
    fi

    # Save raw output alongside report
    echo "$copilot_output" >> "${output_file%.md}-copilot-raw.txt"
    print_success "Copilot analysis complete${chunk_label:+ (${chunk_label})}" >&2
    echo "$copilot_output"
}

# ---------------------------------------------------------------------------
# Save a ready-to-paste prompt for manual VS Code Copilot use
# ---------------------------------------------------------------------------
save_manual_prompt() {
    local prompt="$1"
    local report_path="$2"
    local suffix="${3:-}"
    local prompt_file="${report_path%.md}-copilot-prompt${suffix}.md"

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
# Full Copilot pipeline: chunk files → run per chunk → merge output
# ---------------------------------------------------------------------------
generate_copilot_section() {
    local pr_number="$1"
    local merge_base="$2"
    local pr_title="$3"
    local pr_author="$4"
    local pr_base="$5"
    local report_path="$6"

    local chunk_size="${COPILOT_CHUNK_SIZE:-10}"

    # Get all changed source files (ts, html, scss — skip json resource files)
    local source_files
    mapfile -t source_files < <(list_changed_files "$pr_number" "$merge_base" \
        | grep -v '\.json$')

    local total_files=${#source_files[@]}

    if [[ $total_files -eq 0 ]]; then
        echo "> _No source files changed — AI analysis skipped._"
        return
    fi

    # Calculate chunks
    local total_chunks=$(( (total_files + chunk_size - 1) / chunk_size ))

    print_step "Running GitHub Copilot AI analysis..." >&2
    if [[ $total_chunks -gt 1 ]]; then
        print_info "${total_files} files → ${total_chunks} chunks of up to ${chunk_size} files each" >&2
    fi

    # Remove stale raw output file from previous runs
    rm -f "${report_path%.md}-copilot-raw.txt"

    local all_output=""
    local chunks_succeeded=0
    local chunks_failed=0
    local i=0
    local chunk_num=0

    while [[ $i -lt $total_files ]]; do
        local chunk=("${source_files[@]:$i:$chunk_size}")
        (( chunk_num += 1 ))

        local chunk_label=""
        [[ $total_chunks -gt 1 ]] && chunk_label="chunk ${chunk_num}/${total_chunks}"

        local prompt
        prompt=$(build_review_prompt \
            "$pr_number" "$merge_base" "$pr_title" "$pr_author" "$pr_base" \
            "$chunk_num" "$total_chunks" "${chunk[@]}")

        # Save manual prompt for this chunk (suffix -c1, -c2, etc. if multiple)
        local prompt_suffix=""
        [[ $total_chunks -gt 1 ]] && prompt_suffix="-c${chunk_num}"
        save_manual_prompt "$prompt" "$report_path" "$prompt_suffix" > /dev/null

        local chunk_output
        chunk_output=$(run_copilot_analysis "$prompt" "$report_path" "$chunk_label")
        local chunk_exit=$?

        if [[ $chunk_exit -eq 0 && -n "$chunk_output" ]]; then
            if [[ -n "$all_output" ]]; then
                # Separator between chunks in the report
                all_output+=$'\n\n---\n\n'
                all_output+="### Part ${chunk_num}/${total_chunks} — Files $(( i + 1 ))–$(( i + ${#chunk[@]} )) of ${total_files}"$'\n\n'
            elif [[ $total_chunks -gt 1 ]]; then
                all_output+="### Part ${chunk_num}/${total_chunks} — Files 1–${#chunk[@]} of ${total_files}"$'\n\n'
            fi
            all_output+="$chunk_output"
            (( chunks_succeeded += 1 ))
        else
            (( chunks_failed += 1 ))
        fi

        (( i += chunk_size ))
    done

    if [[ -n "$all_output" ]]; then
        if [[ $chunks_failed -gt 0 ]]; then
            all_output+=$'\n\n> ⚠️ '"_${chunks_failed} of ${total_chunks} chunk(s) did not return a Copilot response. Check the prompt files for manual review._"
        fi
        echo "$all_output"
    else
        # All chunks failed — show fallback message with prompt file links
        local prompt_files_note=""
        for (( c=1; c<=total_chunks; c++ )); do
            local suffix=""
            [[ $total_chunks -gt 1 ]] && suffix="-c${c}"
            prompt_files_note+="> - \`${report_path%.md}-copilot-prompt${suffix}.md\`"$'\n'
        done

        cat <<EOF
> ⚠️ **Copilot CLI analysis was not available for this run.**
>
> Ready-to-paste prompt files have been saved:
${prompt_files_note}>
> **To get AI analysis:**
> 1. Open VS Code Copilot Chat
> 2. Paste the contents of a prompt file
> 3. Copy the response back into this section of the report

EOF
    fi
}

