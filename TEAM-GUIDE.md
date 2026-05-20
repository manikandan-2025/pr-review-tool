# PAS PR Review Tool — Complete Team Guide

> **Version**: 2.0 | **Maintained by**: Team Lead / Senior Developer  
> Works with any repo registered in `config/repos.conf` (e.g. `dedalus-cis4u/pas-ou`, `dedalus-cis4u/pas-4u-ci`)

---

## Table of Contents

1. [Why This Tool Exists](#1-why-this-tool-exists)
2. [What the Tool Does — Overview](#2-what-the-tool-does--overview)
3. [How It Works — The Full Pipeline](#3-how-it-works--the-full-pipeline)
4. [Prerequisites](#4-prerequisites)
5. [First-Time Setup](#5-first-time-setup)
6. [Using the Tool — Step by Step](#6-using-the-tool--step-by-step)
7. [Jira Integration](#7-jira-integration)
8. [Understanding the Report](#8-understanding-the-report)
9. [All Rules the Tool Checks](#9-all-rules-the-tool-checks)
10. [Managing Review Rules](#10-managing-review-rules)
11. [GitHub Copilot AI Analysis](#11-github-copilot-ai-analysis)
12. [Credential Safety](#12-credential-safety)
13. [Troubleshooting](#13-troubleshooting)
14. [Glossary](#14-glossary)
15. [FAQ](#15-faq)

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
- ✅ **Jira story/defect context** is fetched automatically so the AI knows what the PR is supposed to solve
- ✅ **GitHub Copilot AI** adds deeper analysis beyond what patterns can catch — Jira-aware when context is provided
- ✅ A **structured Markdown report** is generated with every finding categorized, explained, and linked to a fix
- ✅ Works with **multiple repositories** — switch between `pas-ou`, `pas-4u`, or any repo from the menu

**A full review of a 50-file PR now takes under 5 minutes.**

---

## 2. What the Tool Does — Overview

```
You run:  ./pr-review.sh --pr 878
```

```
┌──────────────────────────────────────────────────────────────────┐
│  STEP 1: Fetch PR Info                                           │
│  Gets title, author, base branch from the GitHub API            │
├──────────────────────────────────────────────────────────────────┤
│  STEP 2: Jira Context (optional)                                 │
│  Fetches the linked Jira story — summary, status, acceptance     │
│  criteria, attachments — so the AI knows what to verify         │
├──────────────────────────────────────────────────────────────────┤
│  STEP 3: Checkout                                                │
│  Downloads PR #878 code into an isolated folder                  │
│  Your current work: UNTOUCHED                                    │
├──────────────────────────────────────────────────────────────────┤
│  STEP 4: Analyze                                                 │
│  Scans all changed files against 60+ rules                      │
│  Finds: console.log, missing OnDestroy, hardcoded URLs,         │
│         typos, missing translations, empty methods...            │
├──────────────────────────────────────────────────────────────────┤
│  STEP 5: AI Review                                               │
│  GitHub Copilot reads the diff, rules, AND Jira context         │
│  Verifies code matches stated requirements                        │
│  Provides narrative analysis: logic issues, design smells       │
├──────────────────────────────────────────────────────────────────┤
│  STEP 6: Report                                                  │
│  Generates: reports/pr-878-review-2026-05-20.md                 │
│  Contains: every violation grouped by severity with             │
│            file:line reference, code snippet, fix suggestion     │
│            + Jira context section (if fetched)                  │
└──────────────────────────────────────────────────────────────────┘
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

### 3.3 Jira Context Enrichment

Before analysis begins, the tool optionally fetches the **Jira story or defect** that the PR relates to:

```
Tool asks: "Fetch Jira context for this review? [y/N]"

If yes:
  → "Jira issue key (e.g. HPAS-1234):"
  → curl -H "Authorization: Bearer $JIRA_PAT" https://jira.company.com/rest/api/2/issue/HPAS-1234
  → Parses: summary, type, status, priority, assignee, labels, description, acceptance criteria
  → Result is injected into the Copilot prompt AND saved in the report
```

This lets the AI answer: *"Does the code actually implement what was requested?"*

### 3.4 The Analysis Engine

Once the changed files are known, the tool runs 16 pattern scanners across every `.ts`, `.html`, `.scss`, and `.json` file in the PR:

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
  └─ ... (11 more scanners)
```

Each finding is stored with: **severity | rule ID | file path | line number | matched code | explanation**.

### 3.5 Report Generation

All findings are assembled into a structured Markdown document:

```
pr-878-review-2026-05-20.md
├── Header (PR info, reviewer, date)
├── Executive Summary (counts per severity)
├── Verdict (BLOCKED / NEEDS CHANGES / APPROVED)
├── 📋 Jira Story / Defect Context (if fetched)
├── 🔴 Blockers section
│     └── Each finding: file:line, code snippet, rule, fix
├── 🟠 Major Issues section
├── 🟡 Minor Issues section
├── 🤖 AI Analysis (Copilot narrative — Jira-aware)
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

### Step 1: Clone the tool

```bash
git clone https://github.com/manikandan-2025/pr-review-tool.git ~/pas-project/pr-review-tool
cd ~/pas-project/pr-review-tool
chmod +x pr-review.sh
```

### Step 2: Clone the target repositories (if not done already)

```bash
# pas-ou (Angular frontend)
git clone https://github.com/dedalus-cis4u/pas-ou.git ~/pas-project/pas-ou

# pas-4u-ci (if you review that repo too)
git clone https://github.com/dedalus-cis4u/pas-4u-ci.git ~/pas-project/pas-4u-ci
```

### Step 3: Register your repos in `config/repos.conf`

Open `config/repos.conf` and add a line per repo in this format:

```
alias|github-owner/repo-name|/absolute/path/to/local/clone
```

**Example:**

```
pas-ou|dedalus-cis4u/pas-ou|/home/yourname/pas-project/pas-ou
pas-4u|dedalus-cis4u/pas-4u-ci|/home/yourname/pas-project/pas-4u-ci
```

> 💡 You can also add repos interactively: run the tool and choose **Option 7 → Manage Repositories → Add Repo**

### Step 4: Set your active repository

Open `config/settings.conf` and set:

```bash
ACTIVE_REPO="pas-ou"   # must match an alias in repos.conf
```

Or switch anytime from the menu: **Option 7 → Switch Active Repo**

### Step 5: Set up Jira integration (recommended)

Run the tool and choose **Option 8 — Configure Jira Integration**.

You will need:
- Your Jira instance URL — e.g. `https://jira.yourcompany.com`
- A Personal Access Token (PAT) — generate it at:  
  `<jira-url>/secure/ViewProfile.jspa` → **Personal Access Tokens** → **Create token**

Your PAT is saved to `config/secrets.conf` — a file that is **gitignored and chmod 600** (never committed to git). See [Section 12 — Credential Safety](#12-credential-safety) for details.

### Step 6: Verify everything works

```bash
cd ~/pas-project/pr-review-tool
./pr-review.sh --help
```

You should see the help text with usage and current active repo.

---

## 6. Using the Tool — Step by Step

### Starting the tool

```bash
cd ~/pas-project/pr-review-tool
./pr-review.sh
```

You will see the main menu:

```
  ╔═══════════════════════════════════════════════════════════╗
  ║          PAS  ·  PR Code Review Tool                      ║
  ║          dedalus-cis4u/pas-ou                             ║
  ╚═══════════════════════════════════════════════════════════╝

  Active repo: pas-ou  (dedalus-cis4u/pas-ou)

  1) Review a Pull Request          ← Start here
  2) View Review Rules
  3) Edit Review Rules
  4) Add a New Rule
  5) View Past Reports
  6) Clean Up PR Checkouts
  7) Manage Repositories
  8) Configure Jira Integration
  0) Exit

  → Enter choice [0-8]:
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

▶ Jira Story / Defect Context
  ℹ  Fetch Jira details so Copilot can verify the PR matches its requirements.
  ?  Fetch Jira context for this review? [y/N]: y
  → Jira issue key (e.g. HPAS-1234): HPAS-10454
  ⠋  Contacting Jira API...
  ✔  Jira context loaded for HPAS-10454 — included in AI review prompt.

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

  ✔  Saved to: /home/you/pr-review-tool/reports/pr-878-review-2026-05-20.md

  Quick stats:
      🔴 Blockers : 4
      🟠 Major    : 62
      🟡 Minor    : 9

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
  1)  pr-878-review-2026-05-01.md     1492 lines
  2)  pr-900-review-2026-05-10.md      843 lines
  3)  pr-918-review-2026-05-19.md     2104 lines

  → Enter report number to open (or press Enter to skip):
```

---

### Option 6: Clean Up PR Checkouts

Shows all isolated PR directories and lets you remove them:

```
  PR              Path                                Size
  ──────────────────────────────────────────────────
  pr-878          /home/.../checkouts/pr-878/         124M
  pr-900          /home/.../checkouts/pr-900/          98M

  → Enter PR number to remove (or 'all' to remove all, Enter to cancel):
```

> 💡 **Tip**: Clean up old checkouts periodically. Each one uses disk space (~100–200 MB).

---

### Option 7: Manage Repositories

Add, remove, or switch the active repository — no config file editing needed.

```
  1) Switch Active Repo      ← Change which repo is reviewed
  2) Add Repo                ← Register a new repo (alias|gh-repo|local-path)
  3) Remove Repo             ← Unregister a repo
  4) List Repos              ← See all registered repos
  0) Back to main menu
```

**Example: switching from `pas-ou` to `pas-4u`:**

```
  → Enter number or alias to switch to: pas-4u
  ✔  Switched to 'pas-4u' (dedalus-cis4u/pas-4u-ci)
```

All future reviews in this session will now target `pas-4u`. The setting is persisted to `config/settings.conf`.

---

### Option 8: Configure Jira Integration

First-time Jira setup or PAT rotation:

```
══════════════════════════════════════════════════
  Jira Integration Setup
══════════════════════════════════════════════════

ℹ  You need a Personal Access Token (PAT):
   → https://jira.yourcompany.com/secure/ViewProfile.jspa → Personal Access Tokens

  → Jira URL (e.g. https://jira.yourcompany.com): https://jira.dedalus.com
  → Personal Access Token (input hidden):
  → Jira REST API version (default: 2): 2
  → Acceptance Criteria custom field ID (optional): customfield_10028

ℹ  Testing Jira connection...
✔  Connected as: Manikandan A
✔  Jira credentials saved.
```

Your PAT is stored in `config/secrets.conf` (gitignored, `chmod 600`). The URL and API version go into `config/settings.conf` (safe to commit).

---

### Shortcut: Direct PR review (skip the menu)

If you know the PR number, skip the menu entirely:

```bash
./pr-review.sh --pr 878
```

---

## 7. Jira Integration

### What it does

When you link a Jira story or defect to a review, the tool:

1. Fetches the **issue summary, type, status, priority, assignee, labels, components**
2. Extracts the **description and acceptance criteria** (including custom fields)
3. Lists any **attachments** (screenshots, specs)
4. Injects all of this into the **Copilot AI prompt** so the AI can verify the code actually solves the stated problem
5. Includes a **Jira context section** in the Markdown report

### How to set it up (one time)

Run the tool and choose **Option 8 — Configure Jira Integration**, or:

```bash
./pr-review.sh
# Choose: 8) Configure Jira Integration
```

You will need a **Personal Access Token (PAT)**:
1. Go to `<jira-url>/secure/ViewProfile.jspa`
2. Click **Personal Access Tokens** → **Create token**
3. Give it a name (e.g. "pr-review-tool"), set no expiry or a long one
4. Copy the token — you only see it once!

Enter the URL and paste the token when prompted. The tool tests the connection immediately and shows your name if it works.

### Using Jira during a review

When you run a review, you'll be asked:

```
▶ Jira Story / Defect Context
  ?  Fetch Jira context for this review? [y/N]:
```

Press `y` and enter the issue key (e.g. `HPAS-1234` or `PAS-567`). The tool fetches and displays:

```
  ✔  Jira context loaded for HPAS-1234 — included in AI review prompt.
```

### What the Jira section looks like in a report

```markdown
## 📋 Jira Story / Defect Context

### 📋 Jira Context: [HPAS-1234](https://jira.yourcompany.com/browse/HPAS-1234)
| Field | Value |
|---|---|
| **Type** | Story |
| **Status** | In Progress |
| **Priority** | High |
| **Assignee** | Manikandan A |
| **Labels** | frontend, angular |

**Summary:** Add patient discharge date validation to the case form

**Acceptance Criteria:**
- Date cannot be set in the past
- A warning is shown if date is more than 30 days in the future
- Form submit is blocked if date is invalid
```

### What the AI does differently with Jira context

Without Jira:
> "Review the diff against these coding rules and identify violations."

With Jira:
> "Review the diff against these coding rules AND verify that the implementation matches the Jira story. Flag any acceptance criteria that are missing or unaddressed."

This is particularly useful for catching PRs that are technically clean but don't actually solve the stated requirement.

---

## 8. Understanding the Report

The report is a Markdown file saved in `reports/`. Here is what each section means:

### 8.1 Header

```markdown
# Code Review Report — PR #878

> **🔴 BLOCKED**

| Field         | Value                                              |
|---------------|----------------------------------------------------|
| **PR**        | #878 — HPAS-10454 [FR] ORBIS U: Emergency discharge |
| **Author**    | berndschneiders                                    |
| **Base Branch** | dev/main_ORBIS-U-FR-discharge                  |
| **Merge Base** | 975d6532...                                       |
| **Review Date** | 2026-05-20 11:40                                |
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

### 8.2 Executive Summary

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

### 8.3 Jira Context Section (when fetched)

If a Jira story was fetched, a full context block appears right after the summary. This lets anyone reading the report understand what the PR was supposed to achieve.

---

### 8.4 Individual Finding

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

### 8.5 Recommendations Section

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

## 9. All Rules the Tool Checks

### 9.1 Automatically Detected (Mechanical Checks)

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

### 9.2 AI-Detected (GitHub Copilot Analysis)

These cannot be reliably detected by grep alone — they require understanding intent and context:

| Type | Examples |
|------|---------|
| **Logic errors** | Wrong variable used in calculation, off-by-one in loops, incorrect null checks |
| **Design smells** | God component doing too much, missing abstraction layer, violation of single responsibility |
| **Angular patterns** | Wrong lifecycle hook usage, missing `ChangeDetectionStrategy.OnPush`, `async` pipe not used where it should be |
| **Jira requirement gaps** | Acceptance criteria that are missing from the implementation (only when Jira context is provided) |
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

## 10. Managing Review Rules

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

## 11. GitHub Copilot AI Analysis

### What it does

After the mechanical checks, the tool builds a **structured prompt** containing:

1. A summary of all review rules
2. The `git diff` of all changed files (up to 15 files)
3. **Jira story context** (summary, status, acceptance criteria) — if fetched
4. A request to identify violations, verify requirements, and assess overall quality

This prompt is sent to **GitHub Copilot CLI** (`gh copilot`), which returns a narrative analysis — the kind of deeper review that an experienced developer would provide.

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

## 12. Credential Safety

This section is important for everyone — especially anyone who handles the Jira PAT.

### What credentials does the tool use?

| Credential | Where it comes from | Where it is stored |
|---|---|---|
| **GitHub token** | `gh auth login` (managed by GitHub CLI) | GitHub CLI's secure keyring — NOT in this repo |
| **Jira PAT** | Generated at your Jira profile page | `config/secrets.conf` — gitignored, chmod 600 |

### The `secrets.conf` file

```
config/
├── settings.conf       ← Safe to commit — only URLs, versions, non-sensitive settings
├── secrets.conf        ← NEVER commit — contains your JIRA_PAT (gitignored, chmod 600)
└── secrets.conf.example ← Safe to commit — blank template for new team members
```

Key protections on `secrets.conf`:
- Listed in `.gitignore` — git will not track it
- Created with `chmod 600` — only your user account can read it
- **Pre-commit hook** — the tool installs a `.git/hooks/pre-commit` that scans staged files for credential patterns and blocks the commit if any are found

### What to do if you accidentally commit a credential

1. **Immediately rotate the PAT** — go to `<jira-url>/secure/ViewProfile.jspa` → Personal Access Tokens → delete the exposed token → create a new one
2. Remove the credential from git history (contact the team lead — this requires a `git filter-branch` or `git filter-repo` operation)
3. Run **Option 8 — Configure Jira Integration** to save the new PAT

### Setting up `secrets.conf` on a new machine

```bash
cp config/secrets.conf.example config/secrets.conf
chmod 600 config/secrets.conf
# Then run: ./pr-review.sh → Option 8 to configure
```

Or just run **Option 8** — the tool creates `secrets.conf` automatically when it saves your PAT.

---

## 13. Troubleshooting

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
rm -rf ~/pas-project/pr-review-tool/checkouts/pr-878
cd ~/pas-project/pas-ou
git worktree prune
```

### "Failed to fetch PR" error

- Check your internet connection
- Verify `gh auth status` shows you are logged in
- Check that the PR number is correct and the PR exists
- Make sure you have read access to the repository

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

### Jira connection failed (401 Unauthorized)

Your PAT has expired or is invalid. Rotate it:
1. Go to `<jira-url>/secure/ViewProfile.jspa` → Personal Access Tokens
2. Delete the old token → Create a new one
3. Run **Option 8 — Configure Jira Integration** and enter the new PAT

### Jira issue "not found" (404)

The issue key format is wrong or the issue doesn't exist in your Jira instance.
- Check the format: must be `PROJECT-NUMBER` like `HPAS-1234` or `PAS-567`
- Make sure the project key is correct for your Jira instance

### Active repo path not found

The path in `config/repos.conf` doesn't match your local machine. Fix it via **Option 7 → Manage Repositories**, or edit `config/repos.conf` directly.

### "secrets.conf permissions are NNN — should be 600"

The tool warns and auto-fixes this at startup. Or fix manually:
```bash
chmod 600 config/secrets.conf
```

### Disk space — checkouts are large

Each PR checkout uses roughly 100–200 MB. Clean up old ones regularly:
```bash
./pr-review.sh
# Select: 6) Clean Up PR Checkouts
```

Or manually:
```bash
rm -rf ~/pas-project/pr-review-tool/checkouts/pr-878
cd ~/pas-project/pas-ou && git worktree prune
```

---

## 14. Glossary

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
| **Jira PAT** | Personal Access Token for Jira — generated at your Jira profile page. Used to authenticate API calls. Stored in `secrets.conf` only. |
| **`secrets.conf`** | A local-only file (`config/secrets.conf`) that holds your Jira PAT. It is gitignored and `chmod 600` — never committed to git. |
| **`repos.conf`** | The repository registry file (`config/repos.conf`) — maps aliases to GitHub repo names and local clone paths. |
| **active repo** | The repository currently targeted by the tool, set via `ACTIVE_REPO` in `settings.conf` or by using **Option 7**. |

---

## 15. FAQ

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

Copy the file: `reports/pr-878-review-2026-05-20.md` is plain Markdown. You can:
- Open it in VS Code and share the preview
- Copy the raw text into a GitHub PR comment manually
- Attach it to a Jira comment

---

**Q: Do I need Jira set up to use the tool?**

No. Jira is completely optional. You'll be asked at the start of each review — just press `n` (or Enter, since the default is No) to skip. All other features work exactly the same without Jira.

---

**Q: The tool found 62 MAJOR issues — is that normal?**

For a large PR with 37+ changed files, yes — especially if the PR author is newer to the team's conventions. Many are the same rule repeated across multiple files (e.g., one `console.log` per file). The **Recommended Actions** section at the bottom deduplicates these into ~8–10 actual things to fix.

---

**Q: How do I switch between reviewing pas-ou and pas-4u?**

Use **Option 7 → Switch Active Repo** from the main menu. The switch is persisted — all future reviews will target the new repo until you switch back.

---

**Q: Can I add rules for a different repository?**

Yes. Create a separate instructions file (e.g., `pas-4u-review.instructions.md`) and update `INSTRUCTIONS_FILE` in `settings.conf`. You can switch between instruction files from **Option 3 — Edit Rules → list instruction files**.

---

**Q: Is my code sent anywhere?**

The `git diff` of the PR is sent to GitHub Copilot (which is already a GitHub service — the same server that hosts the repository). Nothing is sent to any third party. If your organisation has data-handling concerns, use the fallback prompt with VS Code Copilot Chat (which goes through the same GitHub Copilot service).

---

**Q: What if I don't have Copilot access?**

All mechanical checks work without Copilot. The tool generates the same report — just without the AI narrative section. The fallback prompt file is still saved if you want to use it later.

---

**Q: How do I update the tool when new features are added?**

```bash
cd ~/pas-project/pr-review-tool
git pull origin feat/multi-repo-feature-branch
```

Your `config/settings.conf` and `config/secrets.conf` are not overwritten by git pull. If `config/repos.conf` changes, merge carefully — it contains your personal local paths.

---

*This document covers tool version 2.0. For questions or improvements, contact the senior developer or open a discussion in the team channel.*
