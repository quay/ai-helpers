---
name: assess
description: >
  Generic CVE triage: fetch advisories (NVD, GHSA, Go vuln DB), check package
  presence in dependency manifests, classify verdict, write assessment artifact,
  and post Jira comment. Project workflows supply repo mapping and branch policy.
allowed-tools:
  - Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/cve-fetch-nvd.sh" *)
  - Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/cve-fetch-ghsa.sh" *)
  - Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/cve-fetch-go-vuln.sh" *)
  - Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/cve-compare-versions.sh" *)
  - Bash(bash .claude/scripts/jira-ops.sh *)
  - Bash(curl *)
  - Bash(jq *)
  - Bash(python3 *)
  - Bash(go *)
  - Bash(govulncheck *)
  - Bash(npm *)
  - Bash(pnpm *)
  - Bash(git *)
  - Bash(gh *)
  - Bash(grep *)
  - Bash(find *)
  - Read
  - Write
  - Glob
  - Grep
  - AskUserQuestion
---

# Assess CVE Impact

## Purpose

Mandatory triage gate before any fix attempt. Gather advisory data, determine
whether the project is actually affected, and classify into one of five
categories:

| Verdict | Meaning |
|---------|---------|
| `package-bump` | Direct dependency bump fixes the CVE |
| `go-stdlib` | Go standard library CVE — fix via toolchain/base image |
| `rpm-layer` | Package from RPM/base image, not app deps |
| `code-change-required` | Fix needs code changes beyond a bump |
| `not-affected` | VEX justification applies |

## Inputs (from caller or env)

| Input | Env var | Required |
|-------|---------|----------|
| CVE ID | `CVE_ID` | yes |
| Package name | `PACKAGE` | yes |
| Upstream repo | `UPSTREAM_REPO` | yes |
| Git branch to assess | `GIT_BRANCH` | yes |
| Jira key | `JIRA_KEY` | if available |
| Go module path | `GO_MOD_PATH` | default `.` |
| Artifact output dir | `CVE_ARTIFACT_DIR` | default `artifacts/cve/assess` |
| Clone root | `CVE_CLONE_ROOT` | default `/tmp` |

## Process

### 1. Fetch advisory data

Run the advisory scripts (fall back to Jira description if APIs fail):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/cve-fetch-nvd.sh" "$CVE_ID"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/cve-fetch-ghsa.sh" "$CVE_ID"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/cve-fetch-go-vuln.sh" "$CVE_ID"
```

Extract: affected range, fixed version, ecosystem, affected symbols.

### 2. Clone repo and checkout branch

```bash
REPO_DIR="${CVE_CLONE_ROOT}/assess-${UPSTREAM_REPO//\//__}"
gh repo clone "$UPSTREAM_REPO" "$REPO_DIR" -- --depth=1 2>/dev/null || true
if [ ! -d "$REPO_DIR" ]; then
  echo "ERROR: Failed to clone $UPSTREAM_REPO" >&2
  exit 1
fi
cd "$REPO_DIR"
git fetch origin "$GIT_BRANCH" --depth=1 2>/dev/null || \
  git fetch origin "${CVE_DEFAULT_BRANCH:-master}" --depth=1
git checkout "$GIT_BRANCH" 2>/dev/null || git checkout "${CVE_DEFAULT_BRANCH:-master}"
```

### 3. Check package presence and extract version

Search manifests:

```bash
grep -ri "${PACKAGE}" requirements*.txt setup.py pyproject.toml 2>/dev/null
grep -i "${PACKAGE}" "${GO_MOD_PATH}/go.mod" 2>/dev/null
grep -i "${PACKAGE}" package.json */package.json 2>/dev/null
```

Extract installed version from the relevant manifest/lockfile.

### 4. Classify verdict

**Go stdlib** — package matches `^(crypto|net|encoding|math|os|syscall|archive|compress|html|image|mime|path|regexp|text|unicode)/`:

→ `go-stdlib`

**Version check** — use compare-versions script:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/cve-compare-versions.sh" "$INSTALLED_VERSION" "$FIXED_VERSION"
```

- `affected` → `package-bump`
- `not-affected` → VEX "Vulnerable Code not Present"
- `equal` → `not-affected`

**Not in manifests** — check container build files if `CONTAINERFILE_PATH` is set.
RPM/base image source → `rpm-layer`. Otherwise → `not-affected` (Component not Present).

**Ambiguous** — run symbol analysis:

- Go: `govulncheck -show verbose ./...` — Informational → not in execute path
- Python: grep imports and affected function names
- Node: `npm ls` / `pnpm ls` + grep source usage

**Breaking changes** in advisory → `code-change-required`

### 5. Write assessment artifact

Use `templates/assessment-artifact.md` as the structure. Save to:

```text
${CVE_ARTIFACT_DIR}/${CVE_ID}.md
```

### 6. Post Jira comment

If `JIRA_KEY` is set, post via `jira-ops.sh comment` using the appropriate
template for the verdict. Prefix with `${CVE_JIRA_COMMENT_PREFIX:-[Phase: Assess]}`.

### 7. Cleanup

Remove clone unless verdict is `package-bump` or `go-stdlib` (fix phase may reuse).

## Output

- Assessment artifact at `${CVE_ARTIFACT_DIR}/${CVE_ID}.md`
- Verdict returned to the caller for routing
