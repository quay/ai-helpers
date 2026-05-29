---
name: fix
description: >
  Apply CVE fixes for Quay components. Handles Python, Go dependency,
  Go stdlib, and Node.js CVEs. Creates separate PRs per CVE per branch
  with test results and comprehensive descriptions.
allowed-tools:
  - Bash(bash .claude/scripts/jira-ops.sh *)
  - Bash(bash .claude/scripts/format-and-lint.sh *)
  - Bash(bash .claude/scripts/validate-pr-title.sh *)
  - Bash(git *)
  - Bash(gh *)
  - Bash(curl *)
  - Bash(jq *)
  - Bash(python3 *)
  - Bash(go *)
  - Bash(govulncheck *)
  - Bash(npm *)
  - Bash(npx *)
  - Bash(pip-audit *)
  - Bash(pybuild-deps *)
  - Bash(pip *)
  - Bash(pip3 *)
  - Bash(skopeo *)
  - Bash(make *)
  - Bash(pytest *)
  - Bash(cat *)
  - Bash(echo *)
  - Bash(find *)
  - Bash(ls *)
  - Bash(grep *)
  - Bash(sed *)
  - Bash(timeout *)
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
---

# Fix CVE

## Purpose

Apply remediations for CVEs that the assess skill classified as
`package-bump` or `go-stdlib`. Creates feature branches, applies fixes,
runs tests, verifies the fix, and creates PRs.

**This skill only runs for CVEs that passed the assess gate.** Read the
assessment artifact first to understand what needs to change.

## Execution Style

**Be concise. Brief status + final summary only.**

```text
Fixing CVE-2026-44432 (urllib3) in quay/quay [redhat-3.17]...
  Branch: fix/cve-2026-44432-urllib3-redhat-3.17-attempt-1
  Fix: urllib3 2.2.1 -> 2.3.0 in requirements.txt
  Regenerated requirements-build.txt
  Tests: PASSED (42 passed, 0 failed)
  Post-fix scan: CVE resolved
  PR: https://github.com/quay/quay/pull/456

Fix report: artifacts/quay-cvefix/fixes/fix-implementation-CVE-2026-44432.md
```

## Prerequisites

- Assessment artifact exists at `artifacts/quay-cvefix/assess/CVE-YYYY-XXXXX.md`
- `component-repository-mappings.json` loaded
- GitHub CLI (`gh`) authenticated
- For Python: `pybuild-deps` available
- For Go: `go` toolchain available
- For Node.js: `npm` available

## Process

### 1. Read Assessment Artifact

```bash
ASSESS_FILE="artifacts/quay-cvefix/assess/${CVE_ID}.md"
```

Extract from the artifact:
- Fix category (`package-bump` or `go-stdlib`)
- Package name and current/fixed versions
- Upstream repo and target branch
- Konflux component path (for go-stdlib)

### 2. Branch Cascade Check

**CRITICAL**: Before fixing on any branch, verify the cascade rule.

```bash
# Parse target branch from Jira summary: [quay-X.Y]
TARGET_VERSION="${TARGET_BRANCH}"  # e.g., "3.17"

# Check EOL branches
EOL_BRANCHES=$(jq -r '.eol_branches[]' component-repository-mappings.json)
for EOL in $EOL_BRANCHES; do
  if [ "$TARGET_VERSION" = "$EOL" ]; then
    echo "WARNING: Branch ${TARGET_VERSION} is EOL — skipping"
    exit 0
  fi
done

# If target is a release branch (not master), check master first
if [ "$TARGET_VERSION" != "master" ]; then
  echo "Checking if fix exists on master..."
  cd "$REPO_DIR"
  git fetch origin master
  git checkout master

  # Check if the package is already at the fixed version on master
  MASTER_VERSION=$(_extract_version "$PACKAGE" "$MANIFEST_FILE")
  HIGHER=$(printf '%s\n' "$MASTER_VERSION" "$FIXED_VERSION" | sort -V | tail -1)

  if [ "$HIGHER" != "$MASTER_VERSION" ] || [ "$MASTER_VERSION" = "$FIXED_VERSION" ]; then
    if [ "$HIGHER" != "$MASTER_VERSION" ]; then
      echo "Fix NOT on master yet. Applying to master first..."
      # Apply fix to master first, then come back to the release branch
      _apply_fix_to_branch "master"
    fi
  else
    echo "Fix already on master (${MASTER_VERSION} >= ${FIXED_VERSION})"
  fi
fi
```

### 3. Clone or Reuse Repository

If the assess phase left a clone in `/tmp`, reuse it. Otherwise clone:

```bash
REPO_ORG=$(echo "$UPSTREAM_REPO" | cut -d/ -f1)
REPO_NAME=$(echo "$UPSTREAM_REPO" | cut -d/ -f2)
REPO_DIR="/tmp/${REPO_ORG}/${REPO_NAME}"

if [ ! -d "$REPO_DIR" ]; then
  mkdir -p "/tmp/${REPO_ORG}"
  gh repo clone "$UPSTREAM_REPO" "$REPO_DIR" -- --depth=50
fi
cd "$REPO_DIR"
```

### 4. Check Write Access and Fork if Needed

```bash
PUSH_ACCESS=$(gh api repos/${UPSTREAM_REPO} --jq '.permissions.push' 2>/dev/null)

if [ "$PUSH_ACCESS" != "true" ]; then
  FORK_USER=$(gh api user --jq '.login')
  gh repo fork "$UPSTREAM_REPO" --clone=false 2>/dev/null || true
  gh repo sync "${FORK_USER}/${REPO_NAME}" --source "$UPSTREAM_REPO" --branch "$GIT_BRANCH"
  git remote add fork "https://github.com/${FORK_USER}/${REPO_NAME}.git" 2>/dev/null || true
  PUSH_REMOTE="fork"
  PR_HEAD_PREFIX="${FORK_USER}:"
else
  PUSH_REMOTE="origin"
  PR_HEAD_PREFIX=""
fi
```

### 5. Create Worktree and Fix Branch

Use worktrees to isolate each branch fix:

```bash
GIT_BRANCH="redhat-${TARGET_VERSION}"
# Fall back to master if the release branch doesn't exist
git fetch origin "$GIT_BRANCH" 2>/dev/null || GIT_BRANCH="master"

BRANCH_DIR="/tmp/${REPO_ORG}/${REPO_NAME}-${GIT_BRANCH//\//-}"
git worktree add "$BRANCH_DIR" "$GIT_BRANCH" 2>/dev/null || {
  git worktree remove "$BRANCH_DIR" --force 2>/dev/null
  git worktree add "$BRANCH_DIR" "$GIT_BRANCH"
}
cd "$BRANCH_DIR"
git pull origin "$GIT_BRANCH"

FIX_BRANCH="fix/cve-${CVE_ID}-${PACKAGE}-${GIT_BRANCH//\//-}-attempt-1"

# Handle stale remote branches from previous runs
if git ls-remote --heads "$PUSH_REMOTE" "$FIX_BRANCH" | grep -q "$FIX_BRANCH"; then
  FIX_BRANCH="${FIX_BRANCH/attempt-1/attempt-2}"
fi

git checkout -b "$FIX_BRANCH"
```

### 6. Check for Existing Open PRs

```bash
EXISTING_PR=$(gh pr list --repo "$UPSTREAM_REPO" --state open \
  --base "$GIT_BRANCH" --search "$CVE_ID" \
  --json number,title,url --jq '.[0]' 2>/dev/null)

if [ -z "$EXISTING_PR" ] || [ "$EXISTING_PR" = "null" ]; then
  EXISTING_PR=$(gh pr list --repo "$UPSTREAM_REPO" --state open \
    --base "$GIT_BRANCH" --search "$PACKAGE" \
    --json number,title,url,author \
    --jq '[.[] | select(.author.login | test("dependabot|renovate"; "i"))] | .[0]' \
    2>/dev/null)
fi

if [ -n "$EXISTING_PR" ] && [ "$EXISTING_PR" != "null" ]; then
  PR_URL=$(echo "$EXISTING_PR" | jq -r '.url')
  echo "Existing PR found: ${PR_URL} — skipping"
  # Document and skip
  _write_existing_pr_report "$CVE_ID" "$EXISTING_PR"
  continue
fi
```

### 7. Apply Fix by Type

---

#### 7.1: Python CVE Fix (quay/quay only)

**Step 7.1.1: Bump the package version**

```bash
# Determine which requirements file contains the package
REQ_FILE=""
for f in requirements.txt requirements-dev.txt; do
  if grep -qi "^${PACKAGE}" "$f" 2>/dev/null; then
    REQ_FILE="$f"
    break
  fi
done

if [ -z "$REQ_FILE" ]; then
  echo "WARNING: ${PACKAGE} not found in requirements files"
  # Check if it's a transitive dependency
  grep -ri "${PACKAGE}" requirements*.txt 2>/dev/null
fi

# Escape regex metacharacters in package name (e.g., dots in golang.org/x/net)
ESCAPED_PACKAGE=$(printf '%s\n' "$PACKAGE" | sed 's/[.[\*^$]/\\&/g')

# Update the version pin
# Handle various pin formats: pkg==1.0.0, pkg>=1.0.0, pkg~=1.0.0
sed -i "s/^${ESCAPED_PACKAGE}[=>~!][=<>~!]*.*$/${PACKAGE}>=${FIXED_VERSION}/" "$REQ_FILE"
```

**Step 7.1.2: Regenerate requirements-build.txt**

```bash
pybuild-deps compile requirements.txt -o requirements-build.txt

# WORKAROUND: setuptools 82.x produces broken metadata when used as a build
# dependency, causing pip install failures. Remove the exact pin until the
# upstream bug (https://github.com/pypa/setuptools/issues/XXXX) is resolved.
# This can be removed once pybuild-deps no longer emits setuptools==82.x pins.
sed -i '/^setuptools==82\b/d' requirements-build.txt
```

**Step 7.1.3: Verify the fix**

```bash
# Check that the new version resolves the CVE
grep "${PACKAGE}" requirements-build.txt
pip-audit -r requirements.txt 2>/dev/null | grep -i "${CVE_ID}" && \
  echo "WARNING: CVE still detected" || echo "CVE resolved in scan"
```

---

#### 7.2: Go Dependency CVE Fix

**Step 7.2.1: Update the dependency**

```bash
cd "${GO_MOD_PATH}"

go get "${PACKAGE}@v${FIXED_VERSION}"
go mod tidy
```

**Step 7.2.2: Verify the fix**

```bash
GO_VERSION=$(grep '^go ' go.mod | awk '{print $2}')
if [[ "$GO_VERSION" =~ ^[0-9]+\.[0-9]+$ ]]; then
  GO_VERSION="${GO_VERSION}.0"
fi

SCAN_OUTPUT=$(GOTOOLCHAIN="go${GO_VERSION}" govulncheck -show verbose ./... 2>&1)

if echo "$SCAN_OUTPUT" | grep -q "$CVE_ID"; then
  echo "WARNING: CVE still detected after fix"
  CVE_STILL_PRESENT=true
else
  echo "CVE resolved"
  CVE_STILL_PRESENT=false
fi
```

---

#### 7.3: Go stdlib CVE Fix (via quay-konflux-components)

This fix targets `quay/quay-konflux-components`, not the upstream repo.

**Step 7.3.1: Clone the Konflux repo**

```bash
KONFLUX_DIR="/tmp/quay/quay-konflux-components"
if [ ! -d "$KONFLUX_DIR" ]; then
  gh repo clone "quay/quay-konflux-components" "$KONFLUX_DIR" -- --depth=50
fi
cd "$KONFLUX_DIR"
git checkout main
git pull origin main
```

**Step 7.3.2: Find the latest go-toolset image tag**

```bash
CONTAINERFILE="${KONFLUX_DIR}/${KONFLUX_COMPONENT}Containerfile"

# Extract current go-toolset tag
CURRENT_TAG=$(grep 'go-toolset' "$CONTAINERFILE" | head -1 | \
  grep -oP '(?<=go-toolset:)[^\s]+')

echo "Current go-toolset tag: ${CURRENT_TAG}"

# List available tags from the registry
AVAILABLE_TAGS=$(skopeo list-tags \
  "docker://registry.access.redhat.com/ubi9/go-toolset" 2>/dev/null | \
  jq -r '.Tags[]' | sort -V)

# Find the latest tag in the same major.minor series
TAG_PREFIX=$(echo "$CURRENT_TAG" | grep -oP '^[0-9]+\.[0-9]+')
LATEST_TAG=$(echo "$AVAILABLE_TAGS" | grep "^${TAG_PREFIX}" | tail -1)

echo "Latest go-toolset tag: ${LATEST_TAG}"
```

**Step 7.3.3: Update all go-toolset FROM lines in the Containerfile**

```bash
sed -i "s|go-toolset:${CURRENT_TAG}|go-toolset:${LATEST_TAG}|g" "$CONTAINERFILE"
```

**Step 7.3.4: Create fix branch and PR**

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

The PR targets `quay/quay-konflux-components`, not the upstream repo.

---

#### 7.4: Node.js CVE Fix (quay/quay only)

**Step 7.4.1: Determine which package.json to update**

```bash
# Check root and web/ directories
NODEJS_DIRS=("." "web/")

# For branches <= 3.16, also check config-tool
MINOR_VERSION=$(echo "$TARGET_VERSION" | cut -d. -f2)
if [ "$MINOR_VERSION" -le 16 ] 2>/dev/null; then
  NODEJS_DIRS+=("config-tool/pkg/lib/editor/")
fi
```

**Step 7.4.2: Update the package**

For each directory with a package.json:

```bash
for DIR in "${NODEJS_DIRS[@]}"; do
  if [ -f "${DIR}package.json" ]; then
    cd "${DIR}"

    # Check if package is in this directory's dependency tree
    if npm ls "${PACKAGE}" 2>/dev/null | grep -q "${PACKAGE}"; then
      echo "Updating ${PACKAGE} in ${DIR}..."

      # Try direct update first
      npm update "${PACKAGE}" 2>/dev/null

      # Verify the update
      UPDATED_VERSION=$(npm ls "${PACKAGE}" 2>/dev/null | grep "${PACKAGE}" | \
        grep -oP '[\d]+\.[\d]+\.[\d]+' | head -1)

      if [ -z "$UPDATED_VERSION" ] || \
         [ "$(printf '%s\n' "$UPDATED_VERSION" "$FIXED_VERSION" | sort -V | tail -1)" != "$UPDATED_VERSION" ]; then
        echo "Direct update insufficient, adding override..."
        jq --arg pkg "$PACKAGE" --arg ver "^${FIXED_VERSION}" \
          '.overrides[$pkg] = $ver' package.json > package.json.tmp && \
          mv package.json.tmp package.json
        npm install
      fi

      # Verify
      npm ls "${PACKAGE}"
      npm audit 2>/dev/null | grep -i "${CVE_ID}" && \
        echo "WARNING: CVE still detected" || echo "CVE resolved"
    fi

    cd "$REPO_DIR"
  fi
done
```

---

### 8. Run Tests

Discover and run tests. Results are non-blocking — PR is created even if
tests fail.

```bash
mkdir -p artifacts/quay-cvefix/fixes/test-results
TEST_LOG="artifacts/quay-cvefix/fixes/test-results/test-${CVE_ID}-$(date +%Y%m%d-%H%M%S).log"
TEST_STATUS="NOT_RUN"

# Python tests
if [ -f "Makefile" ] && grep -q "unit-test\|test" Makefile; then
  timeout 600 make unit-test > "$TEST_LOG" 2>&1 && TEST_STATUS="PASSED" || TEST_STATUS="FAILED"
elif [ -f "pytest.ini" ] || [ -f "pyproject.toml" ]; then
  timeout 600 pytest > "$TEST_LOG" 2>&1 && TEST_STATUS="PASSED" || TEST_STATUS="FAILED"
fi

# Go tests
if [ -f "go.mod" ]; then
  timeout 600 go test ./... > "$TEST_LOG" 2>&1 && TEST_STATUS="PASSED" || TEST_STATUS="FAILED"
fi

# Node.js tests
if [ -f "package.json" ] && jq -e '.scripts.test' package.json >/dev/null 2>&1; then
  timeout 600 npm test > "$TEST_LOG" 2>&1 && TEST_STATUS="PASSED" || TEST_STATUS="FAILED"
fi

echo "Test status: ${TEST_STATUS}"
```

### 9. Commit Changes

```bash
git add -A

COMMIT_MSG="fix(cve): ${CVE_ID} - ${PACKAGE} (${JIRA_KEY})

- Update ${PACKAGE} from ${INSTALLED_VERSION} to ${FIXED_VERSION}
- Addresses ${SEVERITY} vulnerability (CVSS ${CVSS_SCORE})

Resolves: ${JIRA_KEY}"

git commit -m "$COMMIT_MSG"
```

### 10. Write Fix Report

Save to `artifacts/quay-cvefix/fixes/fix-implementation-${CVE_ID}.md`. This
artifact is read by the controller when it runs `/dev:pr` to fill in the
PR description template.

```markdown
# Fix Implementation: CVE-YYYY-XXXXX

## Summary
- **CVE**: CVE-YYYY-XXXXX
- **Package**: <package> <old> -> <new>
- **Severity**: <severity> (CVSS <score>)
- **Repository**: <org/repo>
- **Branch**: <branch>
- **Jira**: <PROJQUAY-XXXX>

## Root Cause / Rationale
CVE-YYYY-XXXXX affects <package> versions <affected-range>.
This component uses version <installed-version> which is within the
affected range. Upgrading to <fixed-version> resolves the vulnerability.

## Changes Made
- <file>: <description of change>

## Test Results
- **Status**: PASSED / FAILED / NOT_RUN
- **Command**: <test command>
- **Log**: artifacts/quay-cvefix/fixes/test-results/<log-file>

## Post-fix Verification
- **Scan tool**: <govulncheck / pip-audit / npm audit>
- **CVE resolved**: yes / no

## Backport
- Required: <yes/no>
- Target: <redhat-X.Y branch, if applicable>
```

The fix skill does NOT create the PR. It commits changes and writes the
fix report. The controller then delegates PR creation to the `/dev:pr`
skill, which handles fork management, title validation, the standard PR
description template, and CI polling.

### 11. Cleanup

```bash
# Remove worktree
git -C "$REPO_DIR" worktree remove "$BRANCH_DIR" --force 2>/dev/null

# After all CVEs processed, clean up clones
rm -rf "/tmp/${REPO_ORG}/${REPO_NAME}"*
```

## Output

- `artifacts/quay-cvefix/fixes/fix-implementation-CVE-YYYY-XXXXX.md` — per-CVE fix report (used by `/dev:pr` for PR description)
- `artifacts/quay-cvefix/fixes/existing-pr-CVE-YYYY-XXXXX.md` — if PR already exists
- `artifacts/quay-cvefix/fixes/test-results/` — test execution logs
- Committed changes on a feature branch (PR creation handled by `/dev:pr`)

## Success Criteria

- [ ] Assessment artifact read and fix category confirmed
- [ ] Branch cascade rule enforced (master fixed before release branches)
- [ ] No duplicate PRs created (checked before applying fix)
- [ ] Fix applied using the correct type-specific strategy
- [ ] Tests discovered and executed (results documented)
- [ ] Post-fix verification completed
- [ ] Changes committed on feature branch
- [ ] Fix report artifact written (for `/dev:pr` to consume)
- [ ] `/tmp` clones cleaned up
