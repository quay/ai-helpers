---
name: fix
description: >
  Quay CVE fix orchestrator. Enforces branch cascade and EOL rules, manages
  git worktrees, delegates language fixes to /cve:fix-* plugin skills, and
  Konflux stdlib fixes to fix-konflux-stdlib. PR creation via /dev:pr.
allowed-tools:
  - Bash(bash .claude/scripts/cve-check-existing-pr.sh *)
  - Bash(git *)
  - Bash(gh *)
  - Bash(jq *)
  - Bash(python3 *)
  - Bash(make *)
  - Bash(pytest *)
  - Bash(cat *)
  - Bash(echo *)
  - Bash(grep *)
  - Bash(sed *)
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
---

# Fix CVE (Quay)

## Purpose

Apply remediations for CVEs classified as `package-bump` or `go-stdlib`.
Enforces Quay branch policy, delegates language-specific fixes to the cve
plugin, and writes fix reports for `/dev:pr`.

**Read the assessment artifact first.** PR creation is handled by the
controller via `/dev:pr` — never create PRs inline.

Plugin scripts (e.g. `cve-check-existing-pr.sh`) are installed to
`.claude/scripts/` at session start by Lola — they are not committed under
this workflow. See `.lola-req` and `session-setup.sh`.

## Quay env setup

```bash
export CVE_FIX_ARTIFACT_DIR="artifacts/quay-cvefix/fixes"
export CVE_CLONE_ROOT="/tmp"
export CVE_BRANCH_PREFIX="redhat-"
export CVE_DEFAULT_BRANCH="master"
export CVE_KONFLUX_REPO="quay/quay-konflux-components"
export CVE_PYBUILD_SETUPTOOLS_WORKAROUND="true"   # quay/quay only
```

## Process

### 1. Read assessment artifact

```bash
ASSESS_FILE="artifacts/quay-cvefix/assess/${CVE_ID}.md"
```

Extract: verdict, package, versions, upstream repo, target branch, konflux path.

Abort if verdict is not `package-bump` or `go-stdlib`.

### 2. Branch cascade check (Quay policy)

From `CLAUDE.md` and `component-repository-mappings.json`:

```bash
EOL_BRANCHES=$(jq -r '.eol_branches[]' component-repository-mappings.json)
# Skip EOL branches (3.11, 3.13)

# If target is a release branch, ensure fix exists on master first
# Each branch gets a separate PR — never combine
```

If target is `redhat-X.Y` and fix is not on master, apply to master first.

### 3. Clone repo and check access

```bash
REPO_DIR="/tmp/${UPSTREAM_REPO//\//__}"
gh repo clone "$UPSTREAM_REPO" "$REPO_DIR" -- --depth=50 2>/dev/null || true
# Fork if no push access (same pattern as /dev:pr)
```

### 4. Worktree and fix branch

```bash
GIT_BRANCH="${CVE_BRANCH_PREFIX}${TARGET_BRANCH}"
FIX_BRANCH="fix/cve-${CVE_ID}-${PACKAGE}-${GIT_BRANCH//\//-}-attempt-1"
git worktree add "$BRANCH_DIR" "$GIT_BRANCH"
git checkout -b "$FIX_BRANCH"
```

### 5. Check existing PRs

```bash
bash .claude/scripts/cve-check-existing-pr.sh "$UPSTREAM_REPO" "$GIT_BRANCH" "$CVE_ID" "$PACKAGE"
```

Skip if Dependabot/Renovate or prior CVE PR exists. Document in
`artifacts/quay-cvefix/fixes/existing-pr-${CVE_ID}.md`.

### 6. Apply fix (delegate by type)

| Ecosystem | Delegate to | Quay overrides |
|-----------|-------------|----------------|
| Python (`quay/quay`) | `/cve:fix-python` | `CVE_PYBUILD_SETUPTOOLS_WORKAROUND=true` |
| Go dependency | `/cve:fix-go` | `GO_MOD_PATH` from mappings (e.g. `config-tool/`) |
| Go stdlib | `fix-konflux-stdlib` skill | Konflux Containerfile path |
| Node.js (`quay/quay`) | `/cve:fix-node` | See branch matrix below |

**Node.js branch matrix (Quay-specific — pass to `/cve:fix-node`):**

| Branch | `USE_PNPM_WEB` | `NODEJS_DIRS` |
|--------|----------------|---------------|
| `master`, `redhat-3.17` | `true` | `.` `web/` |
| `redhat-3.16` and older | `false` | `.` `web/` `config-tool/pkg/lib/editor/` |

**pnpm CI rules (master / redhat-3.17 — `web/` only; root is npm only):**

- Use pnpm 10 in `web/` (`.github/workflows/web-ci.yaml`); pnpm 11 strips `overrides:` header
- `web/pnpm-lock.yaml` is authoritative for builds — always verify it shows fixed version
- Root uses `npm update --package-lock-only` only — do not run pnpm at repo root
- Prefer lockfile-only updates in `web/`; use `patch-pnpm-lock.py` if needed
- Validate `web/` with `pnpm install --frozen-lockfile` before push

For Konflux stdlib fixes, follow the `fix-konflux-stdlib` skill instead of
cloning the upstream app repo.

### 7. Run tests (non-blocking)

Discover and run tests. Log to `artifacts/quay-cvefix/fixes/test-results/`.
PR is created even if tests fail.

### 8. Commit (Quay format)

```bash
git commit -m "fix(cve): ${CVE_ID} - ${PACKAGE} (${JIRA_KEY})

- Update ${PACKAGE} from ${INSTALLED_VERSION} to ${FIXED_VERSION}
- Addresses ${SEVERITY} vulnerability (CVSS ${CVSS_SCORE})

Resolves: ${JIRA_KEY}"
```

### 9. Write fix report

Save to `artifacts/quay-cvefix/fixes/fix-implementation-${CVE_ID}.md` using
`templates/fix-report.md` from the cve plugin. The controller reads this when
running `/dev:pr`.

### 10. Cleanup

Remove worktrees. Clean `/tmp` clones after all CVEs processed.

## Output

- Feature branch with committed fix
- Fix report artifact (consumed by `/dev:pr`)
- Test logs in `artifacts/quay-cvefix/fixes/test-results/`

## Success Criteria

- [ ] Branch cascade enforced
- [ ] No duplicate PRs
- [ ] Fix delegated to correct skill (`/cve:fix-*` or `fix-konflux-stdlib`)
- [ ] Tests run and documented
- [ ] Fix report written for `/dev:pr`

## Detailed recipes

For full step-by-step fix commands (pre-extraction reference), see git history
of this file or `enhancements/003-cve-plugin-extraction.md` line mapping.
