# PAS-OU PR Review Tool

> Automated, rule-based code review CLI for the `dedalus-cis4u/pas-ou` Angular repository.  
> Built for the **dedalus-cis4u** team — catches mechanical violations in seconds so you can focus on logic and architecture.

---

## Features

| Feature | Description |
|---------|-------------|
| 🔍 **Isolated Checkout** | Uses `git worktree` — your working directory is never touched |
| 📋 **Rule-Based Scanning** | 60+ rules (NAME, COMP, CLEAN, RES, KARMA, TPL, ARCH) auto-checked via grep |
| 🤖 **Copilot AI Analysis** | Deep narrative analysis via GitHub Copilot CLI |
| 📄 **Markdown Reports** | Severity-grouped findings with rule IDs, file:line refs, fix guidance |
| ✏️ **Rule Management** | View, edit, or add rules via interactive menu |

---

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| `git` | 2.5+ | system package manager |
| `gh` | 2.x | https://cli.github.com |
| `bash` | 4.0+ | system package manager |
| `python3` | 3.6+ | system package manager |
| GitHub Copilot CLI | 1.x | `gh extension install github/gh-copilot` |

Authenticate:

```bash
gh auth login
gh copilot --version   # verify Copilot CLI is available
```

---

## Team Setup (One-Time)

### 1. Clone this repo (Ignore if already cloned in your machine)

```bash
git clone https://github.com/manikandan-2025/pr-review-tool.git
cd pr-review-tool
chmod +x pr-review.sh
```

### 2. Configure your local paths

Edit `config/settings.conf` — only **`REPO_PATH`** needs to be updated:

```bash
# Path to your local clone of dedalus-cis4u/pas-ou
REPO_PATH="/path/to/your/pas-ou"
```

> `INSTRUCTIONS_FILE`, `CHECKOUTS_DIR`, and `REPORTS_DIR` are all auto-resolved relative to the tool directory — no changes needed.

### 3. Clone the pas-ou repo (if you haven't already)

```bash
git clone https://github.com/dedalus-cis4u/pas-ou.git /path/to/your/pas-ou
```

---

## Usage

### Direct PR review (fastest)

```bash
./pr-review.sh --pr 878
```

### Interactive menu

```bash
./pr-review.sh
```

```
╔═══════════════════════════════════════════════════════════╗
║          PAS-OU  ·  PR Code Review Tool                   ║
║          dedalus-cis4u/pas-ou                             ║
╚═══════════════════════════════════════════════════════════╝

  What would you like to do?

  1) Review a Pull Request         ← start here
  2) View Review Rules
  3) Edit Review Rules
  4) Add a New Rule
  5) View Past Reports
  6) Clean Up PR Checkouts
  7) Exit
```

---

## What Happens During a Review

```
./pr-review.sh --pr 879
```

1. **Fetches PR metadata** (title, author, base branch) from GitHub
2. **Creates an isolated worktree** at `checkouts/pr-879/` — your repo is untouched
3. **Finds the merge base** (what the PR diverged from)
4. **Lists all changed files**
5. **Runs 16+ scanners** — one per rule category
6. **Displays findings** in the terminal by severity (Blocker / Major / Minor)
7. **Asks for Copilot AI** deeper analysis (optional, ~30s)
8. **Saves a Markdown report** to `reports/pr-879-review-YYYY-MM-DD.md`

---

## Report Format

Reports are saved as `reports/pr-<N>-review-<date>.md`:

```markdown
# Code Review Report — PR #879

> 🔴 BLOCKED — Must fix 5 blocker(s) before merge

## Executive Summary
| Severity  | Count |
| 🔴 BLOCKER | 5    |
| 🟠 MAJOR   | 25   |
| 🟡 MINOR   | 52   |

## 🔴 Blockers — Must Fix Before Merge

### 1. `COMP-06` — Memory Leak: Missing OnDestroy
- **File:** `discharge-stay-details.component.ts:41`
- **Code:** `this.someService.getData().subscribe(...)`
- **Why:** Subscribing without cleanup causes memory leaks
- **Fix:** Add `@UntilDestroy()` decorator + `takeUntil(this.destroy$)`

## 🤖 AI Analysis (GitHub Copilot)
...

## 📋 Recommended Actions Before Merge
1. [COMP-06] Add @UntilDestroy() to ...
```

---

## Rules Coverage

| Category | Rule IDs | What It Catches |
|----------|----------|-----------------|
| Naming | NAME-01..10 | Typos, casing, boolean naming, mock naming |
| Components | COMP-06..12 | Memory leaks, constructor subscriptions, hardcoded URLs |
| Cleanup | CLEAN-01..06 | console.log, commented code, empty methods, unused imports |
| Resources | RES-01..02 | Missing translation keys across all locale files |
| Templates | TPL-01..05 | Complex ngClass/ngIf, missing data-e2e-id |
| Karma/Tests | KARMA-01..11 | Boilerplate specs, missing mocks |
| Architecture | ARCH-01..02 | Layer violations |

Full rule details: see [pr-review.instructions.md](pr-review.instructions.md) bundled in this repo.

---

## File Structure

```
pr-review-tool/
├── pr-review.sh              # Main entry point — run this
├── pr-review.instructions.md # All 60+ review rules (bundled)
├── config/
│   └── settings.conf         # ← Edit REPO_PATH here
├── lib/
│   ├── utils.sh              # Colors, logging, prompts
│   ├── checkout.sh           # Git worktree management
│   ├── analyze.sh            # Rule violation scanners
│   ├── copilot.sh            # GitHub Copilot AI integration
│   ├── report.sh             # Markdown report generator
│   └── instructions.sh       # Rule file management UI
├── reports/                  # Generated reports (git-ignored)
├── checkouts/                # Isolated PR worktrees (git-ignored)
└── TEAM-GUIDE.md             # Detailed team documentation
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `gh auth status` fails | Run `gh auth login` |
| `fatal: not a git repository` | Run from `pr-review-tool/` directory |
| Worktree already exists error | Run option 6 (Clean Up) then retry |
| Copilot analysis unavailable | Skip — use the generated prompt file in VS Code Copilot Chat |
| Wrong merge base / too many files | Ensure `REPO_PATH` has `origin/main` up to date: `git fetch origin` |
| Missing resource files | Make sure `REPO_PATH` points to the full pas-ou clone |

---

## For Detailed Docs

See **[TEAM-GUIDE.md](TEAM-GUIDE.md)** — 900+ line guide covering every menu option, all rules, report format, CI integration, and FAQ.

---

## Contributing

To add a new review rule:
1. Use menu option **4) Add a New Rule** — it guides you through the fields
2. Or edit `pr-review.instructions.md` directly (see existing rules for format)
3. Grep-based rule scanners live in `lib/analyze.sh` — add a new `scan_*` function and call it from `run_full_analysis()`
