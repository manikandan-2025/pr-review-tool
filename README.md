# PAS PR Code Review Tool

> **An interactive command-line tool that automatically reviews GitHub Pull Requests.**  
> It catches code violations in seconds, fetches Jira story context, runs an AI-powered analysis via GitHub Copilot, and saves a clean Markdown report — so you can focus on logic and architecture instead of hunting for mechanical issues.

---

## 📖 Table of Contents

- [What Does This Tool Do?](#what-does-this-tool-do)
- [Key Features](#key-features)
- [How It Works — Step by Step](#how-it-works--step-by-step)
- [Prerequisites](#prerequisites)
- [First-Time Setup](#first-time-setup) ← **Start here if you're new**
- [Running a Review](#running-a-review)
- [The Interactive Menu](#the-interactive-menu)
- [Jira Integration](#jira-integration)
- [Understanding the Report](#understanding-the-report)
- [Rules Coverage](#rules-coverage)
- [File Structure](#file-structure)
- [Credential Safety](#credential-safety)
- [Troubleshooting](#troubleshooting)
- [Contributing / Adding Rules](#contributing--adding-rules)

---

## What Does This Tool Do?

When a developer opens a Pull Request, this tool:

1. **Downloads the PR branch** into a temporary, isolated folder — your working code is never touched
2. **Scans the changed files** against 60+ coding rules (naming, memory leaks, console.log, hardcoded URLs, etc.)
3. **Optionally fetches the Jira story or defect** linked to the PR so the AI knows what the code should achieve
4. **Runs GitHub Copilot AI** to give a deeper narrative review that considers the Jira requirements
5. **Saves a Markdown report** with severity-grouped findings, file:line references, and fix guidance

Think of it as having an extra senior developer automatically review every PR before it's merged.

---

## Key Features

| Feature | What It Means For You |
|---|---|
| 🔍 **Isolated Checkout** | Uses `git worktree` — your main branch and working directory are never changed |
| 📋 **60+ Rule Scanners** | Covers naming, memory leaks, cleanup, i18n, test quality, architecture — auto-detected |
| 🎫 **Jira Context** | Fetches the linked Jira story/defect so the AI can verify the code actually solves the right problem |
| 🤖 **Copilot AI Review** | GitHub Copilot gives a narrative review of the diff against your rules and Jira requirements |
| 📄 **Markdown Reports** | Severity-grouped report saved to `reports/` with rule IDs, file:line refs, and fix examples |
| 🏢 **Multi-Repo Support** | Switch between multiple repos (e.g. `pas-ou`, `pas-4u`) without editing any config files |
| 🔒 **Credential Safety** | Secrets stored in a gitignored, `chmod 600` file — a pre-commit hook blocks accidental leaks |
| ✏️ **Rule Management** | Add, view, or edit rules directly from the interactive menu |

---

## How It Works — Step by Step

```
You run:  ./pr-review.sh --pr 918
```

```
Step 1 ── Fetch PR metadata (title, author, base branch) from GitHub API
Step 2 ── Ask: "Link a Jira story?" → fetch summary, status, ACs from Jira (optional)
Step 3 ── Download the PR branch into checkouts/pr-918/ (isolated git worktree)
Step 4 ── Find the merge base (the point where this branch diverged from main)
Step 5 ── List all changed .ts / .html / .scss / .json files
Step 6 ── Run 16 scanners → collect BLOCKER / MAJOR / MINOR findings
Step 7 ── Show findings in terminal (colour-coded)
Step 8 ── Run GitHub Copilot AI analysis against the diff + Jira context (optional, ~30s)
Step 9 ── Save report to reports/pr-918-review-2026-05-20.md
Step 10 ─ Ask: "Open the report now?"
```

---

## Prerequisites

## Prerequisites

You need `git`, `gh` (GitHub CLI), `python3`, and `bash 4+` on your machine — that's all. **The `setup.sh` script installs everything else for you** (see First-Time Setup below).

If you prefer to check manually:

| Tool | Min Version | How to check |
|------|-------------|--------------|
| `git` | 2.5+ | `git --version` |
| `gh` (GitHub CLI) | 2.x | `gh --version` — install from https://cli.github.com |
| `bash` | 4.0+ | `bash --version` — pre-installed on Linux/macOS |
| `python3` | 3.6+ | `python3 --version` — pre-installed on most systems |
| GitHub Copilot | any | `gh copilot --version` — `setup.sh` installs this |

---

## First-Time Setup

### The fast way — run `setup.sh` (recommended)

```bash
git clone https://github.com/manikandan-2025/pr-review-tool.git
cd pr-review-tool
chmod +x setup.sh && ./setup.sh
```

`setup.sh` handles everything in one go:

| Step | What it does |
|------|-------------|
| 1 | Checks `git` and `python3` |
| 2 | **Installs `gh` CLI** automatically (apt / dnf / brew — OS detected) |
| 3 | **Logs you into GitHub** — runs `gh auth login` if needed |
| 4 | **Installs GitHub Copilot** extension (or detects it as a built-in) |
| 5 | Creates `config/repos.conf` and **asks for your local repo path** interactively |
| 6 | Creates `config/secrets.conf` for Jira PAT (optional, input is hidden) |
| 7 | Installs the pre-commit security hook |
| 8 | Runs **11-point verification** — shows exactly what passed or needs fixing |

When complete you'll see `11/11 ✔ Setup complete!` and you can run `./pr-review.sh` immediately.

> 💡 Re-run `./setup.sh` at any time to check your setup status or fix a failing step.

---

### Manual setup (if you prefer step-by-step)

<details>
<summary>Click to expand manual steps</summary>

**Step 1 — Clone this tool and the target repo:**

```bash
git clone https://github.com/manikandan-2025/pr-review-tool.git
cd pr-review-tool
chmod +x pr-review.sh

# Clone the repo you want to review (if not already done)
git clone https://github.com/dedalus-cis4u/pas-ou.git ~/pas-project/pas-ou
```

**Step 2 — Install GitHub CLI and Copilot:**

```bash
# Install gh CLI: https://cli.github.com
gh auth login                            # authenticate with GitHub
gh extension install github/gh-copilot  # install Copilot (if not built-in)
gh copilot --version                     # verify
```

**Step 3 — Add your repo to `config/repos.conf`:**

`config/repos.conf` is **gitignored** (personal, per-machine). Create it from the example:

```bash
cp config/repos.conf.example config/repos.conf
```

Then add your repo — paths support `~/` shorthand:

```
pas-ou|dedalus-cis4u/pas-ou|~/pas-project/pas-ou
pas-4u|dedalus-cis4u/pas-4u-ci|~/pas-project/pas-4u-ci
```

Or use the interactive menu: **Option 7 → Manage Repositories → Add a repo**

**Step 4 — Set up Jira (optional):**

Run `./pr-review.sh` → **Option 8 — Configure Jira Integration**

</details>

---

## Running a Review

### Option A — Direct (fastest)

```bash
./pr-review.sh --pr 918
```

Replace `918` with the actual PR number. The tool handles everything automatically.

### Option B — Interactive menu

```bash
./pr-review.sh
```

Then choose **1) Review a Pull Request** and enter the PR number when prompted.

### Option C — Show help

```bash
./pr-review.sh --help
```

---

## The Interactive Menu

```
╔═══════════════════════════════════════════════════════════╗
║          PAS  ·  PR Code Review Tool                      ║
║          dedalus-cis4u/pas-ou                             ║
╚═══════════════════════════════════════════════════════════╝

  Active repo: pas-ou  (dedalus-cis4u/pas-ou)

  1) Review a Pull Request          ← Start here for a new review
  2) View Review Rules              ← Browse all 60+ rules
  3) Edit Review Rules              ← Open rules file in your editor
  4) Add a New Rule                 ← Guided wizard to add a custom rule
  5) View Past Reports              ← Browse previously generated reports
  6) Clean Up PR Checkouts         ← Remove old PR worktrees to free disk space
  7) Manage Repositories           ← Add, remove, or switch active repo
  8) Configure Jira Integration    ← Set up your Jira URL and PAT
  0) Exit
```

| Option | When to Use |
|--------|-------------|
| **1** | Reviewing any PR — this is the main workflow |
| **2** | Before a review, to remind yourself what rules are enforced |
| **3** | When you want to update or refine an existing rule |
| **4** | When your team agrees on a new coding standard to automate |
| **5** | To revisit or share a past review report |
| **6** | After reviewing several PRs — `checkouts/` can grow large |
| **7** | When switching between `pas-ou` and `pas-4u`, or adding a new repo |
| **8** | First time setting up Jira, or after rotating your PAT |

---

## Jira Integration

When you link a Jira story to a review, the tool:

1. Fetches the **issue summary, type, status, priority, assignee, labels**
2. Extracts the **description and acceptance criteria**
3. Injects all of this into the **Copilot AI prompt** — so the AI can verify the code actually implements what was requested
4. Includes a **Jira context section** in the Markdown report

**Example Jira context in a report:**

```markdown
## 📋 Jira Story / Defect Context

### 📋 Jira Context: [HPAS-1234](https://jira.yourcompany.com/browse/HPAS-1234)
| Field | Value |
|---|---|
| **Type** | Story |
| **Status** | In Progress |
| **Priority** | High |
| **Assignee** | John Doe |

**Summary:** Add patient discharge date validation to the form

**Acceptance Criteria:**
- Date cannot be in the past
- Warning shown if date is more than 30 days ahead
```

**How to set it up:**

```bash
./pr-review.sh
# Choose option 8 → Configure Jira Integration
# Enter your Jira URL and Personal Access Token
```

> 🔐 Your PAT is stored in `config/secrets.conf` (gitignored, permissions 600) — it is **never committed to git**.

---

## Understanding the Report

Reports are saved to `reports/pr-<number>-review-<date>.md`.

### Verdict badges

| Badge | Meaning |
|-------|---------|
| ✅ **APPROVED** | No violations found — safe to merge |
| 🟡 **APPROVED WITH COMMENTS** | Minor style issues only — merge at discretion |
| 🟠 **NEEDS CHANGES** | Major violations — should be fixed before merge |
| 🔴 **BLOCKED** | Blocker violations (e.g. memory leaks) — must fix before merge |

### Severity levels

| Level | Label | Examples |
|-------|-------|---------|
| 🔴 | **BLOCKER** | `subscribe()` without `OnDestroy` (memory leak), missing translation keys |
| 🟠 | **MAJOR** | `console.log` left in code, hardcoded API URLs, empty method stubs |
| 🟡 | **MINOR** | Boolean variable without `is`/`has` prefix, mock naming convention |

### Example finding in a report

```markdown
## 🔴 Blockers — Must Fix Before Merge (1)

### 1. `COMP-06` — Memory Leak: Missing OnDestroy

| | |
|---|---|
| **File** | `case-number-assignments-grid.component.ts:41` |
| **Rule** | COMP-06 |
| **Severity** | 🔴 BLOCKER |

**Code:** `this.service.getData().subscribe(result => { ... })`

**Why this matters:**  
Subscribing to an Observable without unsubscribing causes a memory leak.
The subscription stays alive even after the component is destroyed.

**How to fix:**  
Add `@UntilDestroy()` decorator and use `takeUntilDestroyed()` or `takeUntil(this.destroy$)`.
```

---

## Rules Coverage

The tool automatically checks 60+ rules across these categories:

| Category | Rule IDs | What It Catches |
|----------|----------|-----------------|
| **Naming** | NAME-01..10 | Known typos, incorrect casing, boolean variables without `is`/`has` prefix, mock constant naming |
| **Components** | COMP-06..12 | Memory leaks (missing OnDestroy), subscriptions in constructors, hardcoded API URLs |
| **Cleanup** | CLEAN-01..06 | `console.log` left in code, commented-out code blocks, empty method stubs, unused imports |
| **Resources** | RES-01..02 | Translation keys missing in one or more locale JSON files |
| **Templates** | TPL-01..05 | Overly complex `ngClass`/`ngIf`, missing `data-e2e-id` on interactive elements |
| **Tests** | KARMA-01..11 | Boilerplate-only specs, missing mock declarations, weak test coverage |
| **Architecture** | ARCH-01..02 | Business logic placed directly in components instead of services |

> 📝 Full rule details with examples and fix guidance: see **[pr-review.instructions.md](pr-review.instructions.md)**

---

## File Structure

```
pr-review-tool/
│
├── pr-review.sh                  ← Main script — run this!
├── setup.sh                      ← First-time setup — installs everything for new users
├── pr-review.instructions.md     ← All 60+ review rules with examples
│
├── config/
│   ├── repos.conf                ← 🔒 Your repo registry (gitignored — per-machine)
│   ├── repos.conf.example        ← Template — auto-copied on first run
│   ├── settings.conf             ← Team-wide settings (URL, scan extensions, base branch)
│   ├── settings.local.conf       ← 🔒 Your personal settings (active repo — gitignored)
│   ├── secrets.conf              ← 🔒 Your JIRA_PAT (gitignored, chmod 600)
│   └── secrets.conf.example      ← Template — copy to secrets.conf to get started
│
├── lib/
│   ├── utils.sh                  ← Colours, logging, spinner, input prompts
│   ├── repo-config.sh            ← Multi-repo management (load, switch, add, remove, update path)
│   ├── checkout.sh               ← Git worktree: fetch PR, create/remove worktree
│   ├── analyze.sh                ← All rule violation scanners (scan_* functions)
│   ├── copilot.sh                ← GitHub Copilot AI integration
│   ├── report.sh                 ← Markdown report generator
│   ├── jira-context.sh           ← Jira API integration (fetch story/defect context)
│   └── instructions.sh           ← Rule file management UI
│
├── reports/                      ← Generated review reports (gitignored)
├── checkouts/                    ← Isolated PR git worktrees (gitignored)
│
├── README.md                     ← This file
└── TEAM-GUIDE.md                 ← Deep-dive guide for the whole team
```

---

## Credential Safety

This tool handles two types of credentials: your **GitHub token** (managed by `gh auth`) and your **Jira PAT**.

| Rule | Detail |
|------|--------|
| `config/secrets.conf` is **gitignored** | It will never be committed, even by accident |
| `config/secrets.conf` is **chmod 600** | Only your user account can read it |
| `config/repos.conf` is **gitignored** | Your local clone paths stay on your machine |
| `config/settings.local.conf` is **gitignored** | Your active repo preference stays on your machine |
| **Pre-commit hook** blocks leaks | If a real credential pattern is detected in a staged file, the commit is rejected |
| `config/settings.conf` is **clean** | Only non-sensitive, team-wide settings live here |

**If you accidentally expose your Jira PAT:**
1. Go to `<jira-url>/secure/ViewProfile.jspa` → Personal Access Tokens
2. Delete the exposed token and generate a new one
3. Run **Option 8** to reconfigure

---

## Troubleshooting

| Problem | Cause | Solution |
|---------|-------|----------|
| `gh auth status` fails | Not logged into GitHub CLI | Run `gh auth login` or re-run `./setup.sh` |
| `gh copilot --version` fails | Extension not installed | Run `./setup.sh` — it installs it automatically |
| `fatal: not a git repository` | Wrong working directory | Run from `pr-review-tool/` folder |
| Worktree already exists error | Previous checkout left behind | Choose **Option 6 → Clean Up PR Checkouts** then retry |
| Copilot AI returns nothing | CLI unavailable / not authenticated | A prompt file is saved automatically — paste it into VS Code Copilot Chat |
| Wrong number of changed files | Local repo is out of date | Run `git fetch origin` inside your `pas-ou` folder |
| Jira connection failed (401) | PAT expired or wrong | Run **Option 8** and enter a fresh PAT |
| Jira issue "not found" (404) | Wrong issue key format | Check the key format: must be like `HPAS-1234` or `PAS-567` |
| Active repo `⚠ path not found` | Path in `repos.conf` is wrong for this machine | **Option 7 → 4) Update local path** — enter your correct path (supports `~/`) |
| `repos.conf` has no entries | First run after cloning | Run `./setup.sh` step 5, or **Option 7 → 2) Add a repo** |
| `python3: command not found` | Python not installed | `sudo apt install python3` or `brew install python3` |

---

## Contributing / Adding Rules

**To add a new coding rule to the scanner:**

1. **Use the guided wizard** (recommended for beginners):
   ```bash
   ./pr-review.sh
   # Choose option 4 → Add a New Rule
   ```

2. **Or add it manually:**
   - Edit `pr-review.instructions.md` — follow the existing rule table format
   - Add a new `scan_*()` function in `lib/analyze.sh`
   - Call your new function from `run_full_analysis()` at the bottom of `lib/analyze.sh`

3. **Rule format in the instructions file:**
   ```
   | Rule ID | Severity | Description | Example | Fix |
   |---------|----------|-------------|---------|-----|
   | NAME-11 | MINOR    | My new rule | bad code | fix |
   ```

---

## For Detailed Docs

See **[TEAM-GUIDE.md](TEAM-GUIDE.md)** — a comprehensive guide covering every menu option, all 60+ rules with examples, report format details, CI integration ideas, and FAQs.
