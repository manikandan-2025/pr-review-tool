#!/usr/bin/env bash
# =============================================================================
#  report.sh — Generates structured Markdown code review report
# =============================================================================

# ---------------------------------------------------------------------------
# Build report filename: reports/pr-{N}-review-{date}.md
# ---------------------------------------------------------------------------
get_report_path() {
    local pr_number="$1"
    local date_str
    date_str=$(date +%Y-%m-%d)
    echo "${REPORTS_DIR}/pr-${pr_number}-review-${date_str}.md"
}

# ---------------------------------------------------------------------------
# Generate the full Markdown report
# ---------------------------------------------------------------------------
generate_report() {
    local pr_number="$1"
    local pr_title="$2"
    local pr_author="$3"
    local pr_base="$4"
    local pr_created="$5"
    local merge_base="$6"
    local ai_section="$7"
    local jira_context="${8:-}"
    local report_path
    report_path=$(get_report_path "$pr_number")

    local review_date
    review_date=$(date '+%Y-%m-%d %H:%M')
    local reviewer
    reviewer=$(git config user.name 2>/dev/null || echo "$(whoami)")

    local total=$(( COUNT_BLOCKER + COUNT_MAJOR + COUNT_MINOR ))

    # Determine overall verdict
    local verdict verdict_badge
    if [[ $COUNT_BLOCKER -gt 0 ]]; then
        verdict="BLOCKED — Must fix all blockers before merge"
        verdict_badge="🔴 BLOCKED"
    elif [[ $COUNT_MAJOR -gt 0 ]]; then
        verdict="NEEDS CHANGES — Address major violations before merge"
        verdict_badge="🟠 NEEDS CHANGES"
    elif [[ $COUNT_MINOR -gt 0 ]]; then
        verdict="APPROVED WITH COMMENTS — Minor issues noted"
        verdict_badge="🟡 APPROVED WITH COMMENTS"
    else
        verdict="APPROVED — No violations found"
        verdict_badge="✅ APPROVED"
    fi

    {
        # ── Header ──────────────────────────────────────────────────────────
        cat <<HEADER
# Code Review Report — PR #${pr_number}

> **${verdict_badge}**

| Field | Value |
|-------|-------|
| **PR** | [#${pr_number}](https://github.com/${GITHUB_REPO}/pull/${pr_number}) — ${pr_title} |
| **Author** | \`${pr_author}\` |
| **Base Branch** | \`${pr_base}\` |
| **Merge Base** | \`${merge_base}\` |
| **PR Created** | ${pr_created} |
| **Review Date** | ${review_date} |
| **Reviewer** | ${reviewer} |
| **Review Tool** | [pas-ou PR Review Tool](https://github.com/${GITHUB_REPO}) |

---

## Executive Summary

| Severity | Count | Action Required |
|----------|-------|-----------------|
| 🔴 **BLOCKER** | ${COUNT_BLOCKER} | Must fix before merge |
| 🟠 **MAJOR** | ${COUNT_MAJOR} | Should fix before merge |
| 🟡 **MINOR** | ${COUNT_MINOR} | Nice-to-have fixes |
| **TOTAL** | **${total}** | |

### Verdict: ${verdict_badge}

${verdict}

---

HEADER

        # ── Jira Context (if provided) ───────────────────────────────────────
        if [[ -n "$jira_context" ]]; then
            cat <<JIRA_SECTION
## 📋 Jira Story / Defect Context

${jira_context}

---

JIRA_SECTION
        fi

        # ── Findings by Severity ────────────────────────────────────────────
        for severity in BLOCKER MAJOR MINOR; do
            local emoji count section_header
            emoji=$(severity_emoji "$severity")
            case "$severity" in
                BLOCKER) count=$COUNT_BLOCKER; section_header="Blockers — Must Fix Before Merge" ;;
                MAJOR)   count=$COUNT_MAJOR;   section_header="Major Issues — Should Fix Before Merge" ;;
                MINOR)   count=$COUNT_MINOR;   section_header="Minor Issues — Nice to Have" ;;
            esac

            [[ $count -eq 0 ]] && continue

            echo "## ${emoji} ${section_header} (${count})"
            echo ""

            local finding_num=0
            for finding in "${FINDINGS[@]}"; do
                IFS='|' read -r sev rule file line match msg <<< "$finding"
                [[ "$sev" == "$severity" ]] || continue
                (( finding_num += 1 ))

                # Rule description from lookup
                local rule_desc
                rule_desc=$(get_rule_description "$rule")

                cat <<FINDING
### ${finding_num}. \`${rule}\` — ${rule_desc}

| | |
|---|---|
| **File** | \`${file}\` |
| **Line** | ${line} |
| **Rule** | [${rule}](#) |

**Code found:**
\`\`\`
${match}
\`\`\`

**Issue:** ${msg}

**Fix:** $(get_rule_fix "$rule")

---

FINDING
            done
        done

        # ── AI Copilot Analysis ─────────────────────────────────────────────
        cat <<COPILOT
## 🤖 AI Analysis (GitHub Copilot)

${ai_section}

---

COPILOT

        # ── Recommendations ────────────────────────────────────────────────
        echo "## 📋 Recommended Actions Before Merge"
        echo ""
        local action_num=0

        if [[ $COUNT_BLOCKER -gt 0 ]]; then
            # Deduplicate blocker rules
            local blocker_rules=()
            for finding in "${FINDINGS[@]}"; do
                IFS='|' read -r sev rule _ _ _ _ <<< "$finding"
                [[ "$sev" == "BLOCKER" ]] || continue
                if ! printf '%s\n' "${blocker_rules[@]}" | grep -q "^${rule}$"; then
                    blocker_rules+=("$rule")
                    (( action_num += 1 ))
                    echo "${action_num}. **[${rule}]** $(get_rule_fix "$rule")"
                fi
            done
            echo ""
        fi

        if [[ $COUNT_MAJOR -gt 0 ]]; then
            local major_rules=()
            for finding in "${FINDINGS[@]}"; do
                IFS='|' read -r sev rule _ _ _ _ <<< "$finding"
                [[ "$sev" == "MAJOR" ]] || continue
                if ! printf '%s\n' "${major_rules[@]}" | grep -q "^${rule}$"; then
                    major_rules+=("$rule")
                    (( action_num += 1 ))
                    echo "${action_num}. **[${rule}]** $(get_rule_fix "$rule")"
                fi
            done
            echo ""
        fi

        if [[ $COUNT_MINOR -gt 0 ]]; then
            echo "_Minor issues (optional but encouraged):_"
            local minor_rules=()
            for finding in "${FINDINGS[@]}"; do
                IFS='|' read -r sev rule _ _ _ _ <<< "$finding"
                [[ "$sev" == "MINOR" ]] || continue
                if ! printf '%s\n' "${minor_rules[@]}" | grep -q "^${rule}$"; then
                    minor_rules+=("$rule")
                    (( action_num += 1 ))
                    echo "${action_num}. **[${rule}]** $(get_rule_fix "$rule")"
                fi
            done
            echo ""
        fi

        # ── Footer ──────────────────────────────────────────────────────────
        cat <<FOOTER
---

## 📚 Reference

- [Review Instructions](${INSTRUCTIONS_FILE})
- [PR on GitHub](https://github.com/${GITHUB_REPO}/pull/${pr_number})

_Report generated by [pas-ou PR Review Tool](${REPO_PATH}) on ${review_date}_
FOOTER

    } > "$report_path"

    echo "$report_path"
}

# ---------------------------------------------------------------------------
# Rule descriptions (short title for each rule)
# ---------------------------------------------------------------------------
get_rule_description() {
    local rule="$1"
    case "$rule" in
        NAME-01) echo "Inconsistent or verbose variable names" ;;
        NAME-02) echo "Boolean variable missing is/has/can/should prefix" ;;
        NAME-03) echo "Route constant name is ambiguous" ;;
        NAME-04) echo "Hardcoded string literal used with i18n/translate pipe" ;;
        NAME-05) echo "Method name does not describe its action" ;;
        NAME-06) echo "Constants not in ALL_CAPS" ;;
        NAME-07) echo "Component name does not match folder name" ;;
        NAME-08) echo "String literals used where an enum should exist" ;;
        NAME-09) echo "data-cy attribute used instead of data-e2e-id" ;;
        NAME-10) echo "Test attribute ID does not match element purpose" ;;
        COMP-01) echo "Multiple nested if statements" ;;
        COMP-02) echo "Missing error handling for async operations" ;;
        COMP-03) echo "Redundant conditional check" ;;
        COMP-04) echo "Unnecessary new method — existing method can be reused" ;;
        COMP-05) echo "Initialization method called more than once" ;;
        COMP-06) echo "Memory leak: subscribes without OnDestroy cleanup" ;;
        COMP-07) echo "Business logic placed in component instead of service" ;;
        COMP-08) echo "Subscriptions inside constructor instead of ngOnInit" ;;
        COMP-09) echo "Duplicate validator initialization" ;;
        COMP-10) echo "Not using optional chaining" ;;
        COMP-11) echo "Method violates single responsibility principle" ;;
        COMP-12) echo "Hardcoded API URL strings" ;;
        COMP-13) echo "Manually calling setErrors when Validators.required already added" ;;
        COMP-14) echo "Using setTimeout instead of reactive patterns" ;;
        COMP-15) echo "Manual date manipulation instead of date-fns" ;;
        COMP-16) echo "New component created when existing one can be reused" ;;
        COMP-17) echo "Using Map/plain arrays instead of typed value objects" ;;
        COMP-18) echo "Multiple similar @Input() for same type" ;;
        COMP-19) echo "Reusable logic inline — should be extracted to utility" ;;
        SVC-01)  echo "Missing loading state management in service" ;;
        TPL-01)  echo "Template alignment issue" ;;
        TPL-02)  echo "Existing method not used in template" ;;
        TPL-03)  echo "Complex ngClass expression — extract to getter" ;;
        TPL-04)  echo "Long *ngIf condition — extract to boolean getter" ;;
        TPL-05)  echo "Duplicated template — use ng-template" ;;
        RES-01)  echo "Resource key missing from one or more locale files" ;;
        RES-02)  echo "Resource key not designed for global use" ;;
        CLEAN-01) echo "Commented-out code blocks present" ;;
        CLEAN-02) echo "Unused variables/declarations" ;;
        CLEAN-03) echo "Unused import" ;;
        CLEAN-04) echo "console.log statements left in code" ;;
        CLEAN-05) echo "Duplicate file — should be in shared location" ;;
        CLEAN-06) echo "Empty method body (no-op stub)" ;;
        KARMA-01) echo "Spec file has only boilerplate test" ;;
        KARMA-02) echo "Redundant fixture/component initialization" ;;
        KARMA-03) echo "Unrelated assertions in single test case" ;;
        KARMA-04) echo "Mock constant not in ALL_CAPS" ;;
        KARMA-05) echo "Too many granular tests for same scenario" ;;
        KARMA-06) echo "Weak spy assertion — spy reset() is not a real assertion" ;;
        KARMA-07) echo "Unused jasmine.clock() install" ;;
        KARMA-08) echo "Unnecessary markAsTouched() in test" ;;
        KARMA-09) echo "Wrong locale in test initialization" ;;
        KARMA-10) echo "Missing branch coverage in test scenarios" ;;
        KARMA-11) echo "Test data file duplicated — move to shared location" ;;
        PW-01)   echo "Playwright tests not updated for feature change" ;;
        PW-02)   echo "Region-specific conditions not handled in Playwright" ;;
        CUC-01)  echo "Cucumber step definitions not updated" ;;
        CUC-02)  echo "Missing country code check in Cucumber steps" ;;
        ARCH-01) echo "Unnecessary if-else — same logic in both branches" ;;
        ARCH-02) echo "Redundant variable assigned multiple times" ;;
        *)       echo "$rule" ;;
    esac
}

# ---------------------------------------------------------------------------
# Fix recommendations for each rule
# ---------------------------------------------------------------------------
get_rule_fix() {
    local rule="$1"
    case "$rule" in
        NAME-01) echo "Rename variable to a full, descriptive name — avoid abbreviations and redundant words" ;;
        NAME-02) echo "Add 'is', 'has', 'can', or 'should' prefix to boolean variable (e.g., \`isLoading\`, \`hasError\`)" ;;
        NAME-04) echo "Replace the hardcoded string with a \`PAS_*\` resource key from the translations file" ;;
        NAME-06) echo "Rename constant to ALL_CAPS_WITH_UNDERSCORES (e.g., \`MOCK_PATIENT_DATA\`)" ;;
        NAME-08) echo "Create an enum for the string values and use the enum type instead" ;;
        NAME-09) echo "Replace \`data-cy\` with \`data-e2e-id\` throughout the template" ;;
        COMP-06) echo "Add \`@UntilDestroy()\` decorator on the class and use \`takeUntilDestroyed()\` operator on all subscriptions" ;;
        COMP-07) echo "Move the data-fetching / business logic call to a dedicated method in the corresponding service" ;;
        COMP-08) echo "Move \`.subscribe()\` calls from constructor to \`ngOnInit()\` — only validators and \`isRequired\` belong in constructor" ;;
        COMP-12) echo "Extract the URL into a \`private readonly\` constant at the top of the class or service" ;;
        CLEAN-01) echo "Delete the commented-out code block — use git history to recover it if needed" ;;
        CLEAN-04) echo "Remove all \`console.log\` / \`console.warn\` statements before merging" ;;
        CLEAN-06) echo "Either implement the method body or remove the empty stub entirely" ;;
        RES-01)  echo "Add the new resource key to ALL locale files: fr.json, fr_LU.json, de.json, de_CH.json, en_GB.json, en_IE.json, en_AU.json" ;;
        KARMA-01) echo "Add meaningful tests that cover real component behavior (load events, form validation, service calls)" ;;
        NAME-01) echo "Fix the typo in all affected files using a consistent rename" ;;
        TPL-03)  echo "Extract the ngClass logic to a getter method in the component class" ;;
        TPL-04)  echo "Extract the *ngIf condition to a named boolean getter in the component" ;;
        *)       echo "See \`pr-review.instructions.md\` for the full rule definition and example" ;;
    esac
}

# ---------------------------------------------------------------------------
# Print report summary to terminal after generation
# ---------------------------------------------------------------------------
print_report_summary() {
    local report_path="$1"
    local pr_number="$2"

    echo ""
    print_header "Report Generated"
    print_success "Saved to: ${report_path}"
    echo ""
    print_info "Quick stats:"
    echo -e "    🔴 Blockers : ${COUNT_BLOCKER}"
    echo -e "    🟠 Major    : ${COUNT_MAJOR}"
    echo -e "    🟡 Minor    : ${COUNT_MINOR}"
    echo ""
}
