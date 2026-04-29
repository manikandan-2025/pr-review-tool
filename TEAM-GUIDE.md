# PAS-OU PR Review Tool — Complete Team Guide

> **Version**: 1.0 | **Repository**: `dedalus-cis4u/pas-ou` | **Maintained by**: Team Lead / Senior Developer

---

## Table of Contents

1. [Why This Tool Exists](#1-why-this-tool-exists)
2. [What the Tool Does — Overview](#2-what-the-tool-does--overview)
3. [How It Works — The Full Pipeline](#3-how-it-works--the-full-pipeline)
4. [Prerequisites](#4-prerequisites)
5. [First-Time Setup](#5-first-time-setup)
6. [Using the Tool — Step by Step](#6-using-the-tool--step-by-step)
7. [Understanding the Report](#7-understanding-the-report)
8. [All Rules the Tool Checks](#8-all-rules-the-tool-checks)
9. [Managing Review Rules](#9-managing-review-rules)
10. [GitHub Copilot AI Analysis](#10-github-copilot-ai-analysis)
11. [Posting Reports to GitHub](#11-posting-reports-to-github)
12. [Troubleshooting](#12-troubleshooting)
13. [Glossary](#13-glossary)
14. [FAQ](#14-faq)

---

## 1. Why This Tool Exists

### The Problem

Before this tool, reviewing a PR in `dedalus-cis4u/pas-ou` required a reviewer to:

1. Manually stash their current work (`git stash`)
2. Fetch and checkout the PR branch (`git fetch origin pull/878/head:pr-878 && git checkout pr-878`)
3. Manually run `grep` commands across 50+ changed files to look for rule violations
4. Remember all 60+ rules from `pr-review.instructions.md`
5. Write up a findings report by hand
6. Restore their working state (`git checkout my-branch && git stash pop`)

This process took **2–4 hours per PR**, was **error-prone** (rules were missed), and **interrupted the reviewer's own work**.

### The Solution

This tool automates everything:

- ✅ PR code is checked out in a **completely separate directory** — your current work is never touched
- ✅ All 60+ rules are checked **automatically** using pattern scanning
- ✅ **GitHub Copilot AI** adds deeper analysis beyond what patterns can catch
- ✅ A **structured report** is generated with every finding categorized, explained, and linked to a fix
- ✅ The report can be **posted directly** to the GitHub PR as a comment

**A full review of a 50-file PR now takes under 5 minutes.**

---

## 2. What the Tool Does — Overview

```
You run:  ./pr-review.sh
          ↓
          Enter PR number: 878
          ↓
┌─────────────────────────────────────────────────────────────────┐
│  STEP 1: Fetch                                                  │
│  Downloads PR #878 code from GitHub into an isolated folder     │
│  Your current work: UNTOUCHED                                   │
├─────────────────────────────────────────────────────────────────┤
│  STEP 2: Analyze                                                │
│  Scans all 37+ changed files against 15 rule categories        │
│  Finds: console.log, missing OnDestroy, hardcoded URLs,        │
│         typos, missing translations, empty methods...           │
├─────────────────────────────────────────────────────────────────┤
│  STEP 3: AI Review                                              │
│  GitHub Copilot reads the diff and rule set                     │
│  Provides narrative analysis: logic issues, design smells,     │
│  things grep cannot catch                                       │
├─────────────────────────────────────────────────────────────────┤
│  STEP 4: Report                                                 │
│  Generates:  reports/pr-878-review-2025-04-29.md               │
│  Contains: every violation grouped by severity with            │
│            file:line reference, code snippet, fix suggestion    │
├─────────────────────────────────────────────────────────────────┤
│  STEP 5 (optional): Post to GitHub                              │
│  Posts the report as a PR comment with one keypress            │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. How It Works — The Full Pipeline

### 3.1 Isolated Checkout with `git worktree`

Most people use `git checkout` to switch branches, but this **replaces** your current working directory. If you have uncommitted changes, you need to `git stash` first and remember to restore afterwards.

This tool uses a Git feature called **`git worktree`** instead. Think of it like this:

```
Your normal git repository
  /home/you/pas-project/pas-ou/          ← You work here (branch: my-feature)
                                            This is NEVER changed by the tool

  /home/you/pas-project/pr-review-tool/
    checkouts/
      pr-878/                             ← Tool creates THIS (branch: pr-878)
      pr-900/                             ← Another PR reviewed later
```

Both directories point to the **same git repository object store** but can have **different branches checked out simultaneously**. When the tool finishes, you can delete the `checkouts/pr-878/` folder and your repository is completely clean.

### 3.2 Finding What Changed

After checking out the PR, the tool calculates the **merge base** — the last commit that is shared between the PR branch and the main branch. This tells us exactly which files the PR author changed.

```
                            merge base
                                ↓
main:   ──●──●──●──●──●──●──[975d65]──●──●──●──● (current main)
                                 \
PR #878:                          ●──●──[9cbe94] (HEAD of PR)
                                        ↑
                              Only these commits are reviewed
```

The tool uses the GitHub API to get the exact merge base SHA — no guesswork.

### 3.3 The Analysis Engine

Once the changed files are known, the tool runs 15 pattern scanners across every `.ts`, `.html`, `.scss`, and `.json` file in the PR:

```
For each changed file:
  ├─ CLEAN-04: grep for console.log()   → found at line 269, 42, 39...
  ├─ COMP-06:  count .subscribe() calls
  │            count OnDestroy/UntilDestroy declarations
  │            if subscribes > 0 AND cleanup = 0 → BLOCKER
  ├─ COMP-12:  grep for hardcoded URL strings "/api/...", "https://..."
  ├─ NAME-09:  grep for data-cy= in HTML → should be data-e2e-id
  ├─ RES-01:   find new keys in *Resources_en.json
  │            check if those keys exist in fr.json, de.json, en_GB.json...
  │            if missing → BLOCKER
  └─ ... (10 more scanners)
```

Each finding is stored with: **severity | rule ID | file path | line number | matched code | explanation**.

### 3.4 Report Generation

All findings are assembled into a structured Markdown document:

```
pr-878-review-2025-04-29.md
├── Header (PR info, reviewer, date)
├── Executive Summary (counts per severity)
├── Verdict (BLOCKED / NEEDS CHANGES / APPROVED)
├── 🔴 Blockers section
│     └── Each finding: file:line, code snippet, rule, fix
├── 🟠 Major Issues section
├── 🟡 Minor Issues section
├── 🤖 AI Analysis (Copilot narrative)
└── 📋 Recommended Actions list
```

---

## 4. Prerequisites

You need these tools installed on your machine:

| Tool | Purpose | How to check | Install |
|------|---------|--------------|---------|
| `git` (2.5+) | Repository operations and worktrees | `git --version` | Your system package manager |
| `gh` (GitHub CLI) | GitHub API access, Copilot integration | `gh --version` | https://cli.github.com |
| `gh copilot` | AI code analysis | `gh copilot --version` | See below |
| `bash` (4.0+) | Running the tool | `bash --version` | Usually pre-installed on Linux/Mac |
| `python3` | Parsing GitHub API JSON responses | `python3 --version` | Usually pre-installed |

### Installing GitHub CLI (`gh`)

**Linux (Debian/Ubuntu):**
```bash
sudo apt install gh
# or
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list
sudo apt update && sudo apt install gh
```

**Mac:**
```bash
brew install gh
```

### Installing GitHub Copilot CLI extension

```bash
gh extension install github/gh-copilot
gh copilot --version   # verify it works
```

### Authenticating with GitHub

```bash
gh auth login
# Select: GitHub.com → HTTPS → authenticate via browser
# Verify with:
gh auth status
```

You should see:
```
✓ Logged in to github.com account your-username
✓ Token: gho_****
```

---

## 5. First-Time Setup

### Step 1: Get the tool

Copy the `pr-review-tool/` folder from the team shared location to your `pas-project/` directory. Your folder structure should look like:

```
pas-project/
  pas-ou/                    ← Your existing local clone of dedalus-cis4u/pas-ou
  pr-review-tool/            ← The tool (copy this here)
    pr-review.sh
    config/
    lib/
    ...
  pr-review.instructions.md  ← The review rules file (already here)
```

### Step 2: Edit the configuration file

Open `pr-review-tool/config/settings.conf` in any text editor:

```bash
nano pr-review-tool/config/settings.conf
```

You will see:

```bash
# Path to your local clone of dedalus-cis4u/pas-ou
REPO_PATH="/home/orbisu/pas-project/pas-ou"

# Path to the review instructions file
INSTRUCTIONS_FILE="/home/orbisu/pas-project/pr-review.instructions.md"

# Where reports are saved
REPORTS_DIR="/home/orbisu/pas-project/pr-review-tool/reports"

# Where isolated PR branches are checked out
CHECKOUTS_DIR="/home/orbisu/pas-project/pr-review-tool/checkouts"
```

**The only line most people need to change is `REPO_PATH`.**

If your clone is at a different path, update it. For example:
```bash
REPO_PATH="/home/yourname/work/pas-ou"
```

### Step 3: Make the script executable (first time only)

```bash
chmod +x ~/pas-project/pr-review-tool/pr-review.sh
```

### Step 4: Verify everything works

```bash
cd ~/pas-project/pr-review-tool
./pr-review.sh --help
```

You should see the help text. You're ready.

---

## 6. Using the Tool — Step by Step

### Starting the tool

```bash
cd /home/orbisu/pas-project/pr-review-tool
./pr-review.sh
```

You will see the main menu:

```
  ╔═══════════════════════════════════════════════════════════╗
  ║          PAS-OU  ·  PR Code Review Tool                   ║
  ║          dedalus-cis4u/pas-ou                             ║
  ╚═══════════════════════════════════════════════════════════╝

  What would you like to do?

  1) Review a Pull Request
  2) View Review Rules
  3) Edit Review Rules
  4) Add a New Rule
  5) View Past Reports
  6) Clean Up PR Checkouts
  7) Post Report to GitHub PR
  8) Exit

  → Enter choice [1-8]:
```

---

### Option 1: Review a Pull Request

This is the main feature. Press `1` and Enter.

```
  → Enter PR number to review: 878
```

**What happens next (automatic):**

```
ℹ  Fetching PR metadata from GitHub...
   Title:   HPAS-10454 [FR] ORBIS U: Emergency discharge
   Author:  berndschneiders
   Base:    dev/main_ORBIS-U-FR-discharge
   State:   open

▶ Fetching PR #878 from GitHub...
  ⠋ Fetching pull/878/head...
  ✔  PR #878 fetched as branch 'pr-878'

▶ Creating isolated worktree at: /home/you/pr-review-tool/checkouts/pr-878
  ✔  Worktree created

▶ Determining merge base...
  ✔  Merge base: 975d6532

▶ Changed files in PR #878:
  frontend/ui/projects/.../discharge-details.component.ts
  frontend/ui/projects/.../discharge-stay-details.component.ts
  frontend/ui/projects/.../emergency-conclusion-details.component.ts
  ... (37 total)

  Total: 37 files changed

▶ Scanning 37 source files + 9 spec files...
  ✔  Analysis complete: 4 blocker(s), 62 major, 9 minor
```

**You are then asked:**
```
  ?  Run GitHub Copilot AI analysis? (recommended, may take ~30s) [Y/n]:
```

Press Enter (yes) for AI analysis, or `n` to skip.

**The report is generated:**
```
▶ Generating Markdown report...

══════════════════════════════════════════════════
  Report Generated
══════════════════════════════════════════════════

  ✔  Saved to: /home/you/pr-review-tool/reports/pr-878-review-2025-04-29.md

  Quick stats:
      🔴 Blockers : 4
      🟠 Major    : 62
      🟡 Minor    : 9

  ?  Post this report as a comment on PR #878? [Y/n]:
  ?  Open the report now? [Y/n]:
```

---

### Option 2: View Review Rules

Displays all rules from `pr-review.instructions.md` with colour coding:

- 🔴 Red = Blocker rules
- 🟠 Orange = Major rules  
- 🟡 Yellow = Minor rules

This is useful for a quick reference during manual review.

---

### Option 3: Edit Review Rules

Opens `pr-review.instructions.md` in your text editor (`nano` by default, or whatever `$EDITOR` is set to).

Use this when the team agrees on a new rule during a PR review meeting.

---

### Option 4: Add a New Rule

Interactive wizard — no need to manually edit the Markdown file:

```
══════════════════════════════════════════
  Add New Review Rule
══════════════════════════════════════════

ℹ  Last rule ID in file: ARCH-02

  → Rule ID (e.g., COMP-20, NAME-11): COMP-20
  → Severity [Blocker/Major/Minor] (default: Major): Major
  → Short description (one line): Using Array.forEach instead of RxJS operators for stream processing
  → PR reference (e.g., #900, or leave blank): #910

  Paste a short BAD code example (press Enter twice when done):
  someObservable$.subscribe(items => items.forEach(item => this.process(item)));

  Paste a short GOOD code example (press Enter twice when done):
  someObservable$.pipe(mergeMap(items => from(items))).subscribe(item => this.process(item));

  ✔  Rule 'COMP-20' added to: /home/you/pr-review.instructions.md
```

---

### Option 5: View Past Reports

Lists all previously generated reports:

```
  1)  pr-878-review-2025-04-29.md     1492 lines
  2)  pr-900-review-2025-05-02.md      843 lines
  3)  pr-912-review-2025-05-10.md     2104 lines

  → Enter report number to open (or press Enter to skip):
```

---

### Option 6: Clean Up PR Checkouts

Shows all isolated PR directories with their disk usage and lets you remove them:

```
  PR              Path                                Size
  ──────────────────────────────────────────────────
  pr-878          /home/.../checkouts/pr-878/         124M
  pr-900          /home/.../checkouts/pr-900/          98M

  → Enter PR number to remove (or 'all' to remove all, Enter to cancel):
```

> 💡 **Tip**: Clean up old checkouts periodically. Each one uses disk space (roughly the size of the repository).

---

### Option 7: Post Report to GitHub PR

Posts a previously generated report as a comment on the GitHub PR. Useful if you ran the review but forgot to post, or want to re-post after editing the report.

---

### Shortcut: Direct PR review (skip the menu)

If you know the PR number, skip the menu entirely:

```bash
./pr-review.sh --pr 878
```

---

## 7. Understanding the Report

The report is a Markdown file saved in `reports/`. Here is what each section means:

### 7.1 Header

```markdown
# Code Review Report — PR #878

> **🔴 BLOCKED**

| Field         | Value                                              |
|---------------|----------------------------------------------------|
| **PR**        | #878 — HPAS-10454 [FR] ORBIS U: Emergency discharge |
| **Author**    | berndschneiders                                    |
| **Base Branch** | dev/main_ORBIS-U-FR-discharge                  |
| **Merge Base** | 975d6532...                                       |
| **Review Date** | 2025-04-29 11:40                                |
| **Reviewer**  | Manikandan                                         |
```

The **verdict badge** immediately tells you the outcome:

| Badge | Meaning |
|-------|---------|
| 🔴 BLOCKED | Has BLOCKER violations — PR must NOT be merged |
| 🟠 NEEDS CHANGES | Has MAJOR violations — should be fixed before merge |
| 🟡 APPROVED WITH COMMENTS | Only minor issues — merge with awareness |
| ✅ APPROVED | No violations found |

---

### 7.2 Executive Summary

```markdown
## Executive Summary

| Severity    | Count | Action Required         |
|-------------|-------|-------------------------|
| 🔴 BLOCKER  | 4     | Must fix before merge   |
| 🟠 MAJOR    | 62    | Should fix before merge |
| 🟡 MINOR    | 9     | Nice-to-have fixes      |
| **TOTAL**   | **75** |                        |
```

A quick overview you can share with the PR author or post directly as a review summary.

---

### 7.3 Individual Finding

Each violation is reported like this:

```markdown
### 2. `COMP-06` — Memory leak: subscribes without OnDestroy cleanup

| | |
|---|---|
| **File** | `frontend/ui/.../discharge-stay-details.component.ts` |
| **Line** | 41 |
| **Rule** | COMP-06 |

**Code found:**
```
this.dischargeService.getStayInitData().subscribe(data => {
```

**Issue:** Component has .subscribe() but no OnDestroy/UntilDestroy/takeUntilDestroyed — memory leak risk

**Fix:** Add `@UntilDestroy()` decorator on the class and use `takeUntilDestroyed()` operator on all subscriptions
```

This gives the PR author everything they need to locate and fix the issue:
- **Rule ID** — they can look up the full rule context in `pr-review.instructions.md`
- **File + Line** — exact location to navigate to
- **Code found** — the actual offending line
- **Issue** — why this is a problem
- **Fix** — exactly what to do

---

### 7.4 Recommendations Section

At the bottom, the report deduplicates all violations into a prioritized action list:

```markdown
## 📋 Recommended Actions Before Merge

1. **[COMP-06]** Add @UntilDestroy() decorator and takeUntilDestroyed() on all subscriptions
2. **[RES-01]** Add new resource keys to ALL locale files: fr.json, fr_LU.json, de.json...
3. **[CLEAN-04]** Remove all console.log / console.warn statements before merging
4. **[NAME-01]** Fix the typo in all affected files using a consistent rename
```

This is the section to copy-paste into the GitHub review comment for the author.

---

## 8. All Rules the Tool Checks

### 8.1 Automatically Detected (Mechanical Checks)

These are found by scanning the code with pattern matching — fast and deterministic:

| Rule | Severity | What it detects | How it detects |
|------|----------|-----------------|----------------|
| **COMP-06** | 🔴 BLOCKER | Component uses `.subscribe()` but has no `OnDestroy` / `UntilDestroy` / `takeUntilDestroyed` | Counts `subscribe(` calls vs cleanup declarations per file |
| **RES-01** | 🔴 BLOCKER | New `PAS_*` resource key added to `en.json` but missing from `fr.json`, `de.json`, `en_GB.json` etc. | Compares key sets across all `*Resources_*.json` files in the PR diff |
| **CLEAN-04** | 🟠 MAJOR | Active `console.log()`, `console.warn()`, `console.error()` in `.ts` files | Grep — ignores commented-out lines |
| **CLEAN-01** | 🟠 MAJOR | Commented-out code blocks (lines starting with `//` that contain code keywords like `this.`, `return`, `subscribe`) | Grep with code keyword filter |
| **CLEAN-06** | 🟠 MAJOR | Empty method bodies — method defined but immediately closed with no implementation | Line-by-line parse |
| **COMP-07** | 🟠 MAJOR | Direct service data-fetch calls in component files (should be in service) | Grep for `Service.getX()` patterns inside `.component.ts` |
| **COMP-08** | 🟠 MAJOR | `.subscribe()` called inside the `constructor()` block | Parses constructor brace depth |
| **COMP-12** | 🟠 MAJOR | Hardcoded API URL strings like `'/api/...'`, `'https://...'` | Grep for URL patterns in `.ts` files |
| **NAME-01** | 🟠 MAJOR | Known typos — e.g., `countyCode` (should be `countryCode`) | Grep for a dictionary of known typos |
| **NAME-04** | 🟠 MAJOR | Hardcoded string literals piped to `\| translate` or `\| i18n` | Grep in HTML files |
| **NAME-09** | 🟠 MAJOR | `data-cy=` attribute used instead of `data-e2e-id=` | Grep in HTML files |
| **KARMA-01** | 🟠 MAJOR | Spec file has only the boilerplate `'should create'` test with no real test cases | Counts `it(` blocks — flags when ≤ 1 and only `'should create'` |
| **NAME-02** | 🟡 MINOR | Boolean variables without `is`/`has`/`can`/`should` prefix (e.g., `validationActive` instead of `isValidationActive`) | Grep for boolean-typed declarations ending in Mode/Flag/Active/Valid etc. |
| **NAME-06** | 🟡 MINOR | Mock constants in spec files not in `ALL_CAPS` (e.g., `mockPatient` should be `MOCK_PATIENT`) | Grep for `const mock` in `.spec.ts` files |
| **TPL-03** | 🟡 MINOR | Complex inline `[ngClass]` with 3+ conditions — should be extracted to a getter method | Grep for `[ngClass]` with multiple comma-separated entries |
| **TPL-04** | 🟡 MINOR | Very long `*ngIf` conditions (60+ characters) — should be extracted to a boolean getter | Grep for `*ngIf` with long expressions |

---

### 8.2 AI-Detected (GitHub Copilot Analysis)

These cannot be reliably detected by grep alone — they require understanding intent and context:

| Type | Examples |
|------|---------|
| **Logic errors** | Wrong variable used in calculation, off-by-one in loops, incorrect null checks |
| **Design smells** | God component doing too much, missing abstraction layer, violation of single responsibility |
| **Angular patterns** | Wrong lifecycle hook usage, missing `ChangeDetectionStrategy.OnPush`, `async` pipe not used where it should be |
| **Test quality** | Tests that pass but don't actually test the right behaviour |
| **Security** | Sensitive data logged, unvalidated user input, XSS-prone template bindings |
| **Performance** | Expensive operations in `ngOnChanges`, unnecessary re-renders, large imports |

---

### 8.3 Rules Requiring Manual Review

Some rules are architectural or subjective — the tool flags related code, but a human needs to judge:

| Rule | What to look for manually |
|------|--------------------------|
| COMP-01 | Deeply nested `if` blocks that could be flattened |
| COMP-04 | New methods that duplicate existing functionality |
| COMP-11 | Methods that do two unrelated things |
| COMP-16 | New components that duplicate an existing component |
| SVC-01 | Service methods missing `addFetchingCall()` / `fetchingCallFinished()` loading state |
| ARCH-01 | `if-else` blocks where both branches do the same thing |

---

## 9. Managing Review Rules

### Where rules are stored

All rules are in a single file: `pr-review.instructions.md`

This file is the **single source of truth** for the team's review standards. It's based on real review comments from PRs #257, #297, #474, #584, #590, #599, #752, #764, #776, #804, #807.

### Viewing current rules (from the menu)

Select **Option 2 — View Review Rules** from the main menu. Rules are displayed with colour coding and grouped by category.

### Editing rules (from the menu)

Select **Option 3 — Edit Review Rules**. This opens the file in your editor. The file uses standard Markdown with specific tables — keep the same format:

```markdown
| Rule   | Severity | Violation                        |
|--------|----------|----------------------------------|
| COMP-06 | Blocker  | Component subscribes without ... |
```

After editing, save and close the editor.

### Adding a new rule (from the menu)

Select **Option 4 — Add a New Rule** and follow the prompts. The wizard handles the formatting.

### Rule ID conventions

Rule IDs follow the pattern `CATEGORY-NUMBER`:

| Category | Prefix | Covers |
|----------|--------|--------|
| Naming conventions | `NAME-` | Variable names, method names, constants, enums |
| Angular Components | `COMP-` | Component lifecycle, subscriptions, validators, patterns |
| Services | `SVC-` | Loading state, business logic separation |
| Templates (HTML) | `TPL-` | ngClass, ngIf, ng-template, bindings |
| Resources (i18n) | `RES-` | Translation key coverage and naming |
| Cleanup | `CLEAN-` | console.log, commented code, unused imports |
| Karma Tests | `KARMA-` | Unit test quality and patterns |
| Playwright Tests | `PW-` | E2E test coverage |
| Cucumber Tests | `CUC-` | Integration test step definitions |
| Architecture | `ARCH-` | Logic structure, conditional patterns |

When adding a new rule, use the next available number in its category.

---

## 10. GitHub Copilot AI Analysis

### What it does

After the mechanical checks, the tool builds a **structured prompt** containing:

1. A summary of all review rules
2. The `git diff` of all changed files (up to 15 files)
3. A request to identify violations and assess overall quality

This prompt is sent to **GitHub Copilot CLI** (`gh copilot explain`), which returns a narrative analysis — the kind of deeper review that an experienced developer would provide.

### When Copilot CLI is available

When you choose "Yes" to AI analysis, you'll see:

```
▶ Running GitHub Copilot AI analysis...
  ⠋  Asking Copilot to review the diff...
  ✔  Copilot analysis complete
```

The AI response is included in the report under **🤖 AI Analysis (GitHub Copilot)**.

### When Copilot CLI is not available (fallback)

If the CLI doesn't respond (network issues, auth problems, model unavailable), the tool automatically saves a **ready-to-paste prompt file**:

```
⚠  Copilot CLI did not return a response
ℹ  A ready-to-paste prompt has been saved for manual use in VS Code Copilot.
ℹ  Prompt saved to: reports/pr-878-copilot-prompt.md
```

**To use the fallback prompt:**

1. Open VS Code
2. Open Copilot Chat (Ctrl+Shift+I or the chat icon)
3. Open the prompt file: `reports/pr-878-copilot-prompt.md`
4. Copy the entire contents
5. Paste into Copilot Chat and press Enter
6. Copy the response back into the AI section of your report

---

## 11. Posting Reports to GitHub

### During a review (automatic prompt)

At the end of every review, the tool asks:

```
  ?  Post this report as a comment on PR #878? [Y/n]:
```

Press Enter to post. You need write access to the repository.

### After a review (menu option 7)

Select **Option 7 — Post Report to GitHub PR** from the menu. Enter the PR number and select the report file.

### What it looks like on GitHub

The report is posted as a **PR review comment**. Because it's Markdown, GitHub renders it with full formatting — tables, code blocks, severity badges, and links.

The PR author will see a complete, structured review with every issue explained, the exact file and line to fix, and the specific fix to apply.

---

## 12. Troubleshooting

### "gh auth status" shows not logged in

```bash
gh auth login
# Choose: GitHub.com → HTTPS → Login with a web browser
```

### Worktree creation fails with "already exists"

The tool will ask if you want to re-use the existing checkout. Press `y` to reuse it (faster) or `n` to delete and recreate it.

If neither works:
```bash
# Remove it manually
rm -rf /home/orbisu/pas-project/pr-review-tool/checkouts/pr-878
cd /home/orbisu/pas-project/pas-ou
git worktree prune
```

### "Failed to fetch PR" error

- Check your internet connection
- Verify `gh auth status` shows you are logged in
- Check that the PR number is correct and the PR exists
- Make sure you have read access to `dedalus-cis4u/pas-ou`

### Report shows 0 findings (unexpected)

This usually means the `REPO_PATH` in `settings.conf` is wrong, or the merge base calculation picked the wrong commit. 

Check:
```bash
# Verify REPO_PATH is correct
ls /home/yourname/your-path/pas-ou/frontend/

# Verify the PR branch exists
cd /home/yourname/your-path/pas-ou
git branch | grep pr-878
```

### "python3: command not found"

The tool uses Python 3 only for parsing GitHub API JSON. Install it:
```bash
sudo apt install python3     # Debian/Ubuntu
brew install python3          # Mac
```

### Copilot AI analysis always fails

This is not a blocker — the mechanical checks still run and the report is still generated. To debug:
```bash
gh copilot explain "what is a git commit?"   # Basic test
gh copilot --version                          # Check version
```

If Copilot CLI is not installed:
```bash
gh extension install github/gh-copilot
```

### Disk space — checkouts are large

Each PR checkout uses roughly 100–200 MB. Clean up old ones regularly:
```bash
./pr-review.sh
# Select: 6) Clean Up PR Checkouts
```

Or manually:
```bash
rm -rf /home/orbisu/pas-project/pr-review-tool/checkouts/pr-878
cd /home/orbisu/pas-project/pas-ou && git worktree prune
```

---

## 13. Glossary

| Term | Meaning |
|------|---------|
| **git worktree** | A Git feature that lets you check out a branch into a separate directory, without replacing your current working directory. The tool uses this to safely isolate PR code. |
| **merge base** | The last commit that is shared between two branches — the point where the PR branch diverged from main. The tool compares only changes after this point. |
| **BLOCKER** | A violation that must be fixed before the PR can be merged — typically causes bugs, memory leaks, or broken deployments. |
| **MAJOR** | A violation that breaks team standards and should be fixed before merging — but technically the code may still run. |
| **MINOR** | A violation that is good practice to fix but does not block merging. |
| **`pr-review.instructions.md`** | The team's shared rules file — 60+ rules built from real review comments on past PRs. |
| **`gh copilot`** | The GitHub Copilot command-line extension — used to ask Copilot AI questions from the terminal. |
| **resource key** | A `PAS_*` translation key in the `*Resources_*.json` files — must exist in ALL locale files for every supported language and region. |
| **`UntilDestroy` / `takeUntilDestroyed`** | Angular patterns for automatically unsubscribing from RxJS observables when a component is destroyed — prevents memory leaks. |
| **`data-e2e-id`** | The team's standard HTML attribute for targeting elements in automated tests (Playwright, Cypress). The older `data-cy` is not used in this codebase. |

---

## 14. FAQ

**Q: Do I need to be on the `pr-878` branch to review it?**

No. The tool checks out the PR into a completely separate folder (`checkouts/pr-878/`). Your current branch in `pas-ou/` is never changed.

---

**Q: What if the PR has already been merged?**

The tool still works. It fetches the branch from GitHub history and compares it against the merge base. You can review merged PRs for learning purposes or to document past violations.

---

**Q: Can two team members review the same PR at the same time?**

Yes — each person runs the tool on their own machine with their own separate checkout. Reports are generated locally.

---

**Q: How do I share the report with the PR author?**

Two ways:
1. **Post to GitHub** (Option 7 or the prompt at end of review) — the report appears as a PR comment
2. **Copy the file** — `reports/pr-878-review-2025-04-29.md` is plain Markdown, readable anywhere

---

**Q: The tool found 62 MAJOR issues — is that normal?**

For a large PR with 37+ changed files, yes — especially if the PR author is newer to the team's conventions. Many are the same rule repeated across multiple files (e.g., one `console.log` per file). The **Recommended Actions** section at the bottom deduplicates these into ~8–10 actual things to fix.

---

**Q: Can I add rules for a different repository?**

Yes. Create a separate instructions file (e.g., `pas-rtt-review.instructions.md`) and update `INSTRUCTIONS_FILE` in `settings.conf`. You can switch between instruction files from **Option 3 — Edit Rules → list instruction files**.

---

**Q: Is my code sent anywhere?**

The `git diff` of the PR is sent to GitHub Copilot (which is already a GitHub service — the same server that hosts the repository). Nothing is sent to any third party. If your organisation has data-handling concerns, use the fallback prompt with VS Code Copilot Chat (which goes through the same GitHub Copilot service).

---

**Q: What if I don't have Copilot access?**

All mechanical checks work without Copilot. The tool generates the same report — just without the AI narrative section. The fallback prompt file is still saved if you want to use it later.

---

**Q: How do I update the tool when new features are added?**

Copy the updated `pr-review-tool/` folder from the team shared location and replace your local copy. Your `config/settings.conf` will not be overwritten (it's a different file) — but keep a backup just in case.

---

*This document covers tool version 1.0. For questions or improvements, contact the senior developer or open a discussion in the team channel.*
