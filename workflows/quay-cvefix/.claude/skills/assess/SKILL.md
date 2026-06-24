---
name: assess
description: >
  Quay CVE triage wrapper. Parses PROJQUAY ticket format, maps container to
  upstream repo, then delegates to /cve:assess for generic advisory analysis.
allowed-tools:
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
  - Read
  - Write
  - Glob
  - Grep
  - AskUserQuestion
---

# Assess CVE Impact (Quay)

## Purpose

Quay-specific wrapper around `/cve:assess`. Handles PROJQUAY ticket parsing,
component mapping, and branch naming before delegating generic triage to the
cve plugin.

## Quay-specific setup

Set these before invoking `/cve:assess`:

```bash
export CVE_ARTIFACT_DIR="artifacts/quay-cvefix/assess"
export CVE_CLONE_ROOT="/tmp"
export CVE_BRANCH_PREFIX="redhat-"
export CVE_DEFAULT_BRANCH="master"
export CVE_JIRA_COMMENT_PREFIX="[Phase: Assess]"
```

## Process

### 1. Parse PROJQUAY ticket

From Jira summary format:

```text
CVE-YYYY-XXXXX container/name: package: description [quay-X.Y]
```

Extract: `CVE_ID`, `CONTAINER`, `PACKAGE`, `TARGET_BRANCH` (from `[quay-X.Y]`).

Fetch full ticket via Jira API or `jira-ops.sh` for description and advisory links.

### 2. Map container to repository

Load `component-repository-mappings.json`:

```bash
COMPONENT_DATA=$(jq -r --arg c "$CONTAINER" '.components[$c] // empty' \
  component-repository-mappings.json)
UPSTREAM_REPO=$(echo "$COMPONENT_DATA" | jq -r '.upstream_repo')
GO_MOD_PATH=$(echo "$COMPONENT_DATA" | jq -r '.go_mod_path // "."')
KONFLUX_COMPONENT=$(echo "$COMPONENT_DATA" | jq -r '.konflux_component // empty')
GIT_BRANCH="${CVE_BRANCH_PREFIX}${TARGET_BRANCH}"
```

If container not mapped, ask the user for the repository URL.

For Konflux RPM-layer checks, set:

```bash
CONTAINERFILE_PATH="${KONFLUX_COMPONENT%/}/Containerfile"
```

(clone `quay/quay-konflux-components` if needed for Containerfile inspection)

### 3. Delegate to `/cve:assess`

Follow the `/cve:assess` skill with the parsed inputs. Quay-specific
overrides for installed version extraction on `quay/quay`:

**master / redhat-3.17**

```bash
# root (npm)
jq -r --arg pkg "$PACKAGE" \
  '.packages["node_modules/"+$pkg].version // empty' package-lock.json

# web/ (pnpm authoritative)
grep -E "  ${PACKAGE}@" web/pnpm-lock.yaml | head -1
```

**redhat-3.16 and older** — `package-lock.json` in root, `web/`, and
`config-tool/pkg/lib/editor/`:

```bash
for dir in . web/ config-tool/pkg/lib/editor/; do
  jq -r --arg pkg "$PACKAGE" \
    '.packages["node_modules/"+$pkg].version // empty' "${dir}package-lock.json" 2>/dev/null
done
```

Include in Jira comments: `Target Branch: <branch> [quay-X.Y]`.

### 4. Route verdict to controller

Return verdict for controller routing:

| Verdict | Controller action |
|---------|-------------------|
| `package-bump` | → fix skill |
| `go-stdlib` | → fix skill (Konflux path) |
| `rpm-layer` | skip, Jira comment only |
| `not-affected` | skip, VEX comment |
| `code-change-required` | escalate to user |

## Output

- `artifacts/quay-cvefix/assess/CVE-YYYY-XXXXX.md`
- Jira comment on PROJQUAY ticket
- Verdict for controller

## Success Criteria

- [ ] PROJQUAY ticket parsed and component mapped
- [ ] `/cve:assess` completed with Quay branch/version overrides
- [ ] Assessment artifact saved
- [ ] Jira comment posted
