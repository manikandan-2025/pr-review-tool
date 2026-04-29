#!/usr/bin/env bash
# =============================================================================
#  analyze.sh — Deterministic rule-based violation scanner
#  Runs grep checks against changed files in the PR worktree
#  and populates FINDINGS array with structured results.
#
#  Finding format (one per array element, pipe-separated):
#    SEVERITY|RULE_ID|FILE|LINE|MATCH_TEXT|MESSAGE
# =============================================================================

# Global findings array — populated by scan_* functions
declare -a FINDINGS=()

COUNT_BLOCKER=0
COUNT_MAJOR=0
COUNT_MINOR=0

# ---------------------------------------------------------------------------
# Helper: add a finding
# ---------------------------------------------------------------------------
add_finding() {
    local severity="$1"   # BLOCKER | MAJOR | MINOR
    local rule_id="$2"
    local file="$3"
    local line="$4"
    local match="$5"
    local message="$6"

    FINDINGS+=("${severity}|${rule_id}|${file}|${line}|${match}|${message}")

    case "$severity" in
        BLOCKER) (( COUNT_BLOCKER += 1 )) ;;
        MAJOR)   (( COUNT_MAJOR += 1 )) ;;
        MINOR)   (( COUNT_MINOR += 1 )) ;;
    esac
}

# ---------------------------------------------------------------------------
# Helper: grep a file in the worktree for a pattern, add findings
# ---------------------------------------------------------------------------
grep_file() {
    local worktree="$1"
    local rel_file="$2"
    local pattern="$3"
    local severity="$4"
    local rule_id="$5"
    local message="$6"
    local abs_file="${worktree}/${rel_file}"

    [[ -f "$abs_file" ]] || return

    while IFS=: read -r lineno match; do
        local trimmed_match
        trimmed_match=$(echo "$match" | sed 's/^[[:space:]]*//')
        add_finding "$severity" "$rule_id" "$rel_file" "$lineno" "$trimmed_match" "$message"
    done < <(grep -n -E "$pattern" "$abs_file" 2>/dev/null)
}

# ---------------------------------------------------------------------------
# CLEAN-04: console.log() left in source code
# ---------------------------------------------------------------------------
scan_console_log() {
    local worktree="$1"; shift
    local files=("$@")

    for f in "${files[@]}"; do
        [[ "$f" == *.ts ]] || continue
        local abs_file="${worktree}/${f}"
        [[ -f "$abs_file" ]] || continue
        # Only match active (non-commented) console.* calls
        while IFS=: read -r lineno match; do
            local trimmed
            trimmed=$(echo "$match" | sed 's/^[[:space:]]*//')
            # Skip lines where console.log is inside a comment
            echo "$trimmed" | grep -qE '^\s*//' && continue
            add_finding "MAJOR" "CLEAN-04" "$f" "$lineno" "$trimmed" \
                "console.log/warn/error must be removed before merge"
        done < <(grep -n -E 'console\.(log|warn|error|debug|info)\(' "$abs_file" 2>/dev/null)
    done
}

# ---------------------------------------------------------------------------
# CLEAN-01: Commented-out code blocks
# ---------------------------------------------------------------------------
scan_commented_code() {
    local worktree="$1"; shift
    local files=("$@")

    for f in "${files[@]}"; do
        [[ "$f" == *.ts || "$f" == *.html ]] || continue
        # Match lines that are commented out and look like real code (not documentation)
        grep_file "$worktree" "$f" \
            '^\s*//(.*)(this\.|\.subscribe|\.pipe|return |const |let |if \()' \
            "MAJOR" "CLEAN-01" \
            "Commented-out code must be removed (use git history to recover)"
    done
}

# ---------------------------------------------------------------------------
# COMP-06 / BLOCKER: subscribe() without OnDestroy/UntilDestroy
# ---------------------------------------------------------------------------
scan_missing_on_destroy() {
    local worktree="$1"; shift
    local files=("$@")

    for f in "${files[@]}"; do
        [[ "$f" == *.ts && "$f" != *.spec.ts ]] || continue
        local abs_file="${worktree}/${f}"
        [[ -f "$abs_file" ]] || continue

        local has_subscribe
        has_subscribe=$(grep -c '\.subscribe(' "$abs_file" 2>/dev/null || true)
        local has_destroy
        has_destroy=$(grep -cE '(OnDestroy|UntilDestroy|takeUntilDestroyed|untilDestroyed)' "$abs_file" 2>/dev/null || true)

        if [[ "$has_subscribe" -gt 0 && "$has_destroy" -eq 0 ]]; then
            # Find the first subscribe line for reporting
            local first_line
            first_line=$(grep -n '\.subscribe(' "$abs_file" 2>/dev/null | head -1 | cut -d: -f1)
            local match
            match=$(grep -n '\.subscribe(' "$abs_file" 2>/dev/null | head -1 | cut -d: -f2- | sed 's/^[[:space:]]*//')
            add_finding "BLOCKER" "COMP-06" "$f" "${first_line:-?}" "$match" \
                "Component has .subscribe() but no OnDestroy/UntilDestroy/takeUntilDestroyed — memory leak risk"
        fi
    done
}

# ---------------------------------------------------------------------------
# COMP-08: subscribe() calls inside constructor
# ---------------------------------------------------------------------------
scan_subscribe_in_constructor() {
    local worktree="$1"; shift
    local files=("$@")

    for f in "${files[@]}"; do
        [[ "$f" == *.ts && "$f" != *.spec.ts ]] || continue
        local abs_file="${worktree}/${f}"
        [[ -f "$abs_file" ]] || continue

        # Extract the constructor block and check for subscribe()
        local in_constructor=0
        local brace_depth=0
        local lineno=0

        while IFS= read -r line; do
            (( lineno += 1 ))
            if echo "$line" | grep -qE 'constructor\s*\('; then
                in_constructor=1
                brace_depth=0
            fi
            if [[ $in_constructor -eq 1 ]]; then
                local opens closes
                opens=$(echo "$line" | tr -cd '{' | wc -c)
                closes=$(echo "$line" | tr -cd '}' | wc -c)
                brace_depth=$(( brace_depth + opens - closes ))

                if echo "$line" | grep -qE '\.subscribe\('; then
                    local trimmed
                    trimmed=$(echo "$line" | sed 's/^[[:space:]]*//')
                    add_finding "MAJOR" "COMP-08" "$f" "$lineno" "$trimmed" \
                        "subscribe() called inside constructor — move data fetch subscriptions to ngOnInit"
                fi

                if [[ $brace_depth -le 0 && $lineno -gt 1 ]]; then
                    in_constructor=0
                fi
            fi
        done < "$abs_file"
    done
}

# ---------------------------------------------------------------------------
# COMP-12: Hardcoded API URL strings in source files
# ---------------------------------------------------------------------------
scan_hardcoded_urls() {
    local worktree="$1"; shift
    local files=("$@")

    for f in "${files[@]}"; do
        [[ "$f" == *.ts ]] || continue
        grep_file "$worktree" "$f" \
            "(['\"])(/api/|/rest/|https?://|/v[0-9]+/)" \
            "MAJOR" "COMP-12" \
            "Hardcoded URL — define as a private readonly constant at the top of the class"
    done
}

# ---------------------------------------------------------------------------
# NAME-09: data-cy attribute instead of data-e2e-id
# ---------------------------------------------------------------------------
scan_data_cy() {
    local worktree="$1"; shift
    local files=("$@")

    for f in "${files[@]}"; do
        [[ "$f" == *.html ]] || continue
        grep_file "$worktree" "$f" \
            'data-cy=' \
            "MAJOR" "NAME-09" \
            "Use 'data-e2e-id' instead of 'data-cy' for test attributes (team standard)"
    done
}

# ---------------------------------------------------------------------------
# NAME-04: Hardcoded string literals piped to | translate / | i18n
# ---------------------------------------------------------------------------
scan_hardcoded_i18n() {
    local worktree="$1"; shift
    local files=("$@")

    for f in "${files[@]}"; do
        [[ "$f" == *.html ]] || continue
        grep_file "$worktree" "$f" \
            "'[A-Z][^']+ [^']+'\s*\|\s*(translate|i18n)" \
            "MAJOR" "NAME-04" \
            "Hardcoded string literal passed to | translate/i18n pipe — use a PAS_* resource key"
    done
}

# ---------------------------------------------------------------------------
# NAME-02: Boolean variables missing is/has/can/should prefix
# ---------------------------------------------------------------------------
scan_boolean_naming() {
    local worktree="$1"; shift
    local files=("$@")

    for f in "${files[@]}"; do
        [[ "$f" == *.ts && "$f" != *.spec.ts ]] || continue
        # Detects: booleanVarName = false/true; without is/has/can/should prefix
        grep_file "$worktree" "$f" \
            '^\s+(public |private |protected )?(readonly )?[a-z][a-zA-Z]+(Mode|Flag|Active|Visible|Enabled|Valid|Required|Mandatory|Loading|Found|Ready)\s*[=:]\s*(false|true|boolean)' \
            "MINOR" "NAME-02" \
            "Boolean variable likely missing 'is'/'has'/'can'/'should' prefix (e.g., isLoading, hasError)"
    done
}

# ---------------------------------------------------------------------------
# NAME-06: Non-CAPS constants (mock/const objects without ALL_CAPS)
# ---------------------------------------------------------------------------
scan_mock_naming() {
    local worktree="$1"; shift
    local files=("$@")

    for f in "${files[@]}"; do
        [[ "$f" == *.spec.ts ]] || continue
        grep_file "$worktree" "$f" \
            'const mock[A-Z]' \
            "MINOR" "NAME-06" \
            "Mock constants must use ALL_CAPS naming (e.g., MOCK_PATIENT instead of mockPatient)"
    done
}

# ---------------------------------------------------------------------------
# CLEAN-06: Empty method bodies (no-op stubs left in code)
# ---------------------------------------------------------------------------
scan_empty_methods() {
    local worktree="$1"; shift
    local files=("$@")

    for f in "${files[@]}"; do
        [[ "$f" == *.ts && "$f" != *.spec.ts ]] || continue
        local abs_file="${worktree}/${f}"
        [[ -f "$abs_file" ]] || continue

        # Match methods that open and immediately close with only whitespace/comment inside
        local lineno=0
        local prev_line=""
        while IFS= read -r line; do
            (( lineno += 1 ))
            local trimmed
            trimmed=$(echo "$line" | sed 's/^[[:space:]]*//')
            if [[ "$trimmed" == "}" ]] && echo "$prev_line" | grep -qE '\)\s*\{$'; then
                local method_match
                method_match=$(echo "$prev_line" | sed 's/^[[:space:]]*//')
                # Only flag non-constructor, non-lifecycle methods
                if ! echo "$method_match" | grep -qE '(constructor|ngOnInit|ngOnDestroy|ngOnChanges|ngAfterViewInit)\s*\('; then
                    add_finding "MAJOR" "CLEAN-06" "$f" "$lineno" "$method_match" \
                        "Empty method body — either implement it or remove the stub"
                fi
            fi
            prev_line="$line"
        done < "$abs_file"
    done
}

# ---------------------------------------------------------------------------
# CLEAN-03: Unused imports (heuristic: imported symbol not found in file body)
# ---------------------------------------------------------------------------
scan_unused_imports() {
    local worktree="$1"; shift
    local files=("$@")

    for f in "${files[@]}"; do
        [[ "$f" == *.ts ]] || continue
        local abs_file="${worktree}/${f}"
        [[ -f "$abs_file" ]] || continue

        while IFS= read -r import_line; do
            # Extract individual symbols from: import { Foo, Bar } from '...'
            local symbols_part
            symbols_part=$(echo "$import_line" | grep -oP '\{\s*\K[^}]+' 2>/dev/null || true)
            [[ -z "$symbols_part" ]] && continue

            IFS=',' read -ra symbols <<< "$symbols_parts"
            while IFS= read -r -d ',' raw_sym; do
                local sym
                sym=$(echo "$raw_sym" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/ as .*//')
                [[ -z "$sym" ]] && continue
                # Check if symbol appears elsewhere in the file (beyond the import line itself)
                local uses
                uses=$(grep -cv "^import" "$abs_file" 2>/dev/null \
                    | xargs -I{} grep -c "\b${sym}\b" "$abs_file" 2>/dev/null || echo 0)
                # A symbol used 1 time or less (only in the import line) is likely unused
                local total_count
                total_count=$(grep -c "\b${sym}\b" "$abs_file" 2>/dev/null || echo 0)
                if [[ "$total_count" -le 1 ]]; then
                    local import_lineno
                    import_lineno=$(grep -n "^import" "$abs_file" 2>/dev/null | grep "$sym" | head -1 | cut -d: -f1)
                    add_finding "MINOR" "CLEAN-03" "$f" "${import_lineno:-?}" "$import_line" \
                        "Potentially unused import '${sym}' — verify and remove if not needed"
                fi
            done <<< "${symbols_part},"
        done < <(grep -E "^import\s+\{" "$abs_file" 2>/dev/null)
    done
}

# ---------------------------------------------------------------------------
# RES-01: New resource keys missing from non-English locale files
# ---------------------------------------------------------------------------
scan_resource_keys() {
    local worktree="$1"
    local pr_number="$2"
    local merge_base="$3"

    # Find resource JSON files
    local resources_dir="${worktree}"
    local en_file
    en_file=$(find "$resources_dir" -name "*Resources_en.json" -not -name "*_GB*" -not -name "*_AU*" -not -name "*_IE*" 2>/dev/null | head -1)

    [[ -z "$en_file" ]] && return

    # Get new keys added to EN file in this PR (lines starting with + in diff, extracting JSON keys)
    local new_keys
    new_keys=$(get_file_diff "$pr_number" "$merge_base" "${en_file#${worktree}/}" \
        | grep '^+' \
        | grep -oP '"PAS_[A-Z_0-9]+"\s*:' \
        | grep -oP '"[^"]+"' \
        | tr -d '"' \
        | sort -u 2>/dev/null)

    [[ -z "$new_keys" ]] && return

    # Find all other locale files
    local locale_files
    mapfile -t locale_files < <(find "$resources_dir" -name "*Resources_*.json" 2>/dev/null | grep -v "$en_file" | sort)

    for key in $new_keys; do
        local missing_locales=()
        for locale_file in "${locale_files[@]}"; do
            if ! grep -q "\"${key}\"" "$locale_file" 2>/dev/null; then
                local locale_name
                locale_name=$(basename "$locale_file")
                missing_locales+=("$locale_name")
            fi
        done

        if [[ ${#missing_locales[@]} -gt 0 ]]; then
            local missing_list
            missing_list=$(printf '%s, ' "${missing_locales[@]}" | sed 's/, $//')
            add_finding "BLOCKER" "RES-01" "${en_file#${worktree}/}" "?" \
                "\"${key}\": \"...\"" \
                "Resource key '${key}' missing from: ${missing_list}"
        fi
    done
}

# ---------------------------------------------------------------------------
# KARMA-01: Spec files with only the boilerplate 'should create' test
# ---------------------------------------------------------------------------
scan_spec_quality() {
    local worktree="$1"; shift
    local spec_files=("$@")

    for f in "${spec_files[@]}"; do
        local abs_file="${worktree}/${f}"
        [[ -f "$abs_file" ]] || continue

        local it_count
        it_count=$(grep -cE "^\s+it\(" "$abs_file" 2>/dev/null || echo 0)
        local has_only_create
        has_only_create=$(grep -c "should create" "$abs_file" 2>/dev/null || echo 0)

        if [[ "$it_count" -le 1 && "$has_only_create" -ge 1 ]]; then
            add_finding "MAJOR" "KARMA-01" "$f" "?" "it('should create', ...)" \
                "Spec file has only boilerplate 'should create' test — add meaningful tests covering the component's behavior"
        fi
    done
}

# ---------------------------------------------------------------------------
# COMP-07: Business logic (API calls) directly in component ngOnInit
# ---------------------------------------------------------------------------
scan_business_logic_in_component() {
    local worktree="$1"; shift
    local files=("$@")

    for f in "${files[@]}"; do
        [[ "$f" == *.ts && "$f" != *.spec.ts ]] || continue
        # Skip service files — only check component files
        echo "$f" | grep -q "\.component\.ts$" || continue
        grep_file "$worktree" "$f" \
            'this\.[a-zA-Z]+Service\.[a-zA-Z]+(Companies|Patients|Records|Data|Items|List|All)\(' \
            "MAJOR" "COMP-07" \
            "Direct service data-fetch call in component — move business/data logic to a dedicated service method"
    done
}

# ---------------------------------------------------------------------------
# NAME-01: Typos in field/variable names (known patterns)
# ---------------------------------------------------------------------------
scan_known_typos() {
    local worktree="$1"; shift
    local files=("$@")

    local -A TYPOS=(
        ["countyCode"]="countryCode — 'county' is a different concept"
        ["recieve"]="receive (spelling error)"
        ["occured"]="occurred (spelling error)"
        ["seperate"]="separate (spelling error)"
    )

    for f in "${files[@]}"; do
        [[ "$f" == *.ts || "$f" == *.html ]] || continue
        for typo in "${!TYPOS[@]}"; do
            local correction="${TYPOS[$typo]}"
            grep_file "$worktree" "$f" \
                "\b${typo}\b" \
                "MAJOR" "NAME-01" \
                "Typo '${typo}' — should be: ${correction}"
        done
    done
}

# ---------------------------------------------------------------------------
# TPL: Angular template issues
# ---------------------------------------------------------------------------
scan_template_issues() {
    local worktree="$1"; shift
    local files=("$@")

    for f in "${files[@]}"; do
        [[ "$f" == *.html ]] || continue
        # TPL-03: Complex ngClass with multiple conditions (could use helper method)
        grep_file "$worktree" "$f" \
            "\[ngClass\]=\"\{.*:.*,.*:.*,.*:.*\}\"" \
            "MINOR" "TPL-03" \
            "Complex inline ngClass expression — consider extracting to a getter method in the component"
        # TPL-04: Duplicate *ngIf blocks with identical structure
        grep_file "$worktree" "$f" \
            "\*ngIf=\"[^\"]{60,}\"" \
            "MINOR" "TPL-04" \
            "Very long *ngIf condition — consider extracting to a readable boolean getter in the component"
    done
}

# ---------------------------------------------------------------------------
# Master scanner: runs all checks and populates FINDINGS
# ---------------------------------------------------------------------------
run_full_analysis() {
    local worktree="$1"
    local pr_number="$2"
    local merge_base="$3"

    # Reset findings
    FINDINGS=()
    COUNT_BLOCKER=0
    COUNT_MAJOR=0
    COUNT_MINOR=0

    # Gather changed files
    local source_files spec_files all_files
    mapfile -t source_files < <(list_changed_files "$pr_number" "$merge_base")
    mapfile -t spec_files   < <(list_changed_spec_files "$pr_number" "$merge_base")
    mapfile -t all_files    < <(list_all_changed_files "$pr_number" "$merge_base")

    print_step "Scanning ${#source_files[@]} source files + ${#spec_files[@]} spec files..."

    scan_console_log          "$worktree" "${source_files[@]}"
    scan_commented_code       "$worktree" "${source_files[@]}"
    scan_missing_on_destroy   "$worktree" "${source_files[@]}"
    scan_subscribe_in_constructor "$worktree" "${source_files[@]}"
    scan_hardcoded_urls       "$worktree" "${source_files[@]}"
    scan_data_cy              "$worktree" "${source_files[@]}"
    scan_hardcoded_i18n       "$worktree" "${source_files[@]}"
    scan_boolean_naming       "$worktree" "${source_files[@]}"
    scan_empty_methods        "$worktree" "${source_files[@]}"
    scan_known_typos          "$worktree" "${source_files[@]}"
    scan_business_logic_in_component "$worktree" "${source_files[@]}"
    scan_template_issues      "$worktree" "${source_files[@]}"
    scan_resource_keys        "$worktree" "$pr_number" "$merge_base"
    scan_spec_quality         "$worktree" "${spec_files[@]}"
    scan_mock_naming          "$worktree" "${spec_files[@]}"
    # Unused import scan is slow — run separately
    # scan_unused_imports     "$worktree" "${source_files[@]}"

    print_success "Analysis complete: ${COUNT_BLOCKER} blocker(s), ${COUNT_MAJOR} major, ${COUNT_MINOR} minor"
}

# ---------------------------------------------------------------------------
# Print findings to terminal (grouped by severity)
# ---------------------------------------------------------------------------
print_findings_terminal() {
    for severity in BLOCKER MAJOR MINOR; do
        local emoji
        emoji=$(severity_emoji "$severity")
        local header_printed=0

        for finding in "${FINDINGS[@]}"; do
            IFS='|' read -r sev rule file line match msg <<< "$finding"
            [[ "$sev" == "$severity" ]] || continue

            if [[ $header_printed -eq 0 ]]; then
                echo -e "\n$(severity_badge "$severity") Findings"
                print_rule
                header_printed=1
            fi

            echo -e "  ${BOLD}[${rule}]${RESET} ${file}:${line}"
            echo -e "  ${DIM}Code:${RESET}    ${match}"
            echo -e "  ${DIM}Reason:${RESET}  ${msg}"
            echo ""
        done
    done
}
