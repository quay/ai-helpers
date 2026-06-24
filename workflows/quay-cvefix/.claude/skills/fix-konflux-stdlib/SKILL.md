---
name: fix-konflux-stdlib
description: >
  Quay-specific Go stdlib CVE fix via quay-konflux-components. Bumps go-toolset
  image tag in the component Containerfile.
allowed-tools:
  - Bash(git *)
  - Bash(gh *)
  - Bash(skopeo *)
  - Bash(jq *)
  - Bash(grep *)
  - Bash(sed *)
  - Read
  - Write
  - Edit
  - Glob
  - Grep
---

# Fix Go stdlib CVE (Konflux)

## Purpose

Go stdlib CVEs for Quay components are fixed by bumping the `go-toolset` image
tag in `quay/quay-konflux-components`, not in the upstream application repo.

## Inputs

From assessment artifact: `CVE_ID`, `PACKAGE`, `JIRA_KEY`, `KONFLUX_COMPONENT`,
`REPO_NAME` (short name for branch naming).

## Process

### 1. Clone Konflux repo

```bash
KONFLUX_DIR="/tmp/quay/quay-konflux-components"
KONFLUX_REPO="${CVE_KONFLUX_REPO:-quay/quay-konflux-components}"
gh repo clone "$KONFLUX_REPO" "$KONFLUX_DIR" -- --depth=50 2>/dev/null || true
cd "$KONFLUX_DIR"
git checkout main && git pull origin main
```

### 2. Find latest go-toolset tag

```bash
CONTAINERFILE="${KONFLUX_DIR}/${KONFLUX_COMPONENT%/}/Containerfile"
CURRENT_TAG=$(grep 'go-toolset' "$CONTAINERFILE" | head -1 | sed -n 's/.*go-toolset:\([^[:space:]]*\).*/\1/p')
AVAILABLE_TAGS=$(skopeo list-tags \
  "docker://registry.access.redhat.com/ubi9/go-toolset" 2>/dev/null | \
  jq -r '.Tags[]' | sort -V)
TAG_PREFIX=$(echo "$CURRENT_TAG" | sed -E 's/^([0-9]+\.[0-9]+).*/\1/')
LATEST_TAG=$(echo "$AVAILABLE_TAGS" | grep "^${TAG_PREFIX}" | tail -1)
```

### 3. Update Containerfile

```bash
sed -i "s|go-toolset:${CURRENT_TAG}|go-toolset:${LATEST_TAG}|g" "$CONTAINERFILE"
```

### 4. Commit on feature branch

```bash
FIX_BRANCH="fix/cve-${CVE_ID}-go-stdlib-${REPO_NAME}-attempt-1"
git checkout -b "$FIX_BRANCH"
git add "$CONTAINERFILE"
git commit -m "fix(cve): ${CVE_ID} - bump go-toolset for ${REPO_NAME} (${JIRA_KEY})

- Update go-toolset from ${CURRENT_TAG} to ${LATEST_TAG}
- Addresses Go stdlib vulnerability in ${PACKAGE}

Resolves: ${JIRA_KEY}"
git push origin "$FIX_BRANCH"
```

PR targets `quay/quay-konflux-components`. Controller delegates PR creation to
`/dev:pr`.

## Output

Committed changes on feature branch in Konflux repo. Fix report written by the
parent fix skill.
