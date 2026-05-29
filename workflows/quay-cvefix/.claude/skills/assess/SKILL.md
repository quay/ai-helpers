---
name: assess
description: >
  CVE triage and impact analysis. Reads advisory data, checks if the
  vulnerable package/symbol is actually used, and classifies into a fix
  category. Posts structured Jira comments with the verdict.
allowed-tools:
  - Bash(bash .claude/scripts/jira-ops.sh *)
  - Bash(curl *)
  - Bash(jq *)
  - Bash(python3 *)
  - Bash(go *)
  - Bash(govulncheck *)
  - Bash(npm *)
  - Bash(pip-audit *)
  - Bash(git *)
  - Bash(gh *)
  - Bash(cat *)
  - Bash(echo *)
  - Bash(find *)
  - Bash(ls *)
  - Bash(grep *)
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
---

# Assess CVE Impact

## Purpose

Mandatory triage gate before any fix attempt. For each CVE, gather advisory
data, determine whether the project is actually affected, and classify
into one of five categories that determines the workflow routing.

## Execution Style

**Be concise. Brief status + final summary only.**

```text
Assessing CVE-2026-44432 (urllib3) for quay/quay-rhel9...
  Advisory: HIGH (CVSS 7.5) - DoS via HTTP decompression
  Package found: requirements.txt urllib3==2.2.1 (affected: <2.3.0)
  Verdict: package-bump (2.2.1 -> 2.3.0)

Assessment saved: artifacts/quay-cvefix/assess/CVE-2026-44432.md
Jira comment posted to PROJQUAY-12345.
```

## Process

### 1. Gather Ticket Data

Fetch the full Jira ticket including description and links:

```bash
JIRA_BASE_URL="https://redhat.atlassian.net"
AUTH=$(echo -n "${JIRA_EMAIL}:${JIRA_API_TOKEN}" | base64 | tr -d '\n')

TICKET_DATA=$(curl -s -X GET \
  --connect-timeout 10 --max-time 30 \
  -H "Authorization: Basic ${AUTH}" \
  -H "Content-Type: application/json" \
  "${JIRA_BASE_URL}/rest/api/3/issue/${JIRA_KEY}?fields=summary,description,issuelinks,status,priority,labels")
```

From the ticket:
- Parse the summary for CVE ID, container, package, target branch
- Read the description for additional context (affected versions, advisory links)
- Extract linked URLs (CVE.org advisory, GitHub Security Advisory)

### 2. Fetch Advisory Data

Consult multiple advisory sources to understand the vulnerability:

**2.1: CVE.org / NVD**

```bash
CVE_ID="CVE-2026-44432"
NVD_DATA=$(curl -s --connect-timeout 10 --max-time 15 \
  "https://services.nvd.nist.gov/rest/json/cves/2.0?cveId=${CVE_ID}")

CVSS_SCORE=$(echo "$NVD_DATA" | jq -r '.vulnerabilities[0].cve.metrics.cvssMetricV31[0].cvssData.baseScore // empty')
SEVERITY=$(echo "$NVD_DATA" | jq -r '.vulnerabilities[0].cve.metrics.cvssMetricV31[0].cvssData.baseSeverity // empty')
CWE=$(echo "$NVD_DATA" | jq -r '.vulnerabilities[0].cve.weaknesses[0].description[0].value // empty')
DESCRIPTION=$(echo "$NVD_DATA" | jq -r '.vulnerabilities[0].cve.descriptions[] | select(.lang=="en") | .value')
```

**2.2: GitHub Security Advisory (GHSA)**

If the Jira ticket links to a GHSA, fetch it. Otherwise search by CVE ID:

```bash
GHSA_DATA=$(gh api graphql -f query='
  query {
    securityAdvisory(ghsaId: "GHSA-XXXX-XXXX-XXXX") {
      summary
      severity
      cvss { score }
      vulnerabilities(first: 10) {
        nodes {
          package { ecosystem name }
          vulnerableVersionRange
          firstPatchedVersion { identifier }
        }
      }
    }
  }
' 2>/dev/null)
```

Or search by CVE alias:

```bash
GHSA_DATA=$(gh api graphql -f query="
  query {
    securityAdvisories(first: 1, identifier: {type: CVE, value: \"${CVE_ID}\"}) {
      nodes {
        ghsaId
        summary
        severity
        cvss { score }
        vulnerabilities(first: 10) {
          nodes {
            package { ecosystem name }
            vulnerableVersionRange
            firstPatchedVersion { identifier }
          }
        }
      }
    }
  }
" 2>/dev/null)
```

Extract from the advisory:
- **Affected version range** (e.g., `< 2.3.0`, `>= 1.0.0 < 1.26.19`)
- **Fixed version** (e.g., `2.3.0`, `1.26.19`)
- **Affected ecosystem** (pip, go, npm)
- **Affected functions/symbols** (if listed in the advisory)

**2.3: Package-specific advisories**

For Go vulnerabilities, check the Go vulnerability database:

```bash
curl -s "https://vuln.go.dev/ID/${CVE_ID}.json" 2>/dev/null | jq '.'
```

This provides exact affected symbols and packages (e.g., `crypto/tls.Config`).

If the NVD or GHSA API calls fail (timeout, rate limit), log a warning and
proceed with whatever data is available. The Jira ticket description often
contains sufficient information.

### 3. Map Container to Repository

Load `component-repository-mappings.json` and look up the container name:

```bash
MAPPING_FILE="component-repository-mappings.json"
COMPONENT_DATA=$(jq -r --arg container "$CONTAINER" \
  '.components[$container] // empty' "$MAPPING_FILE")

UPSTREAM_REPO=$(echo "$COMPONENT_DATA" | jq -r '.upstream_repo')
GITHUB_URL=$(echo "$COMPONENT_DATA" | jq -r '.github_url')
LANGUAGES=$(echo "$COMPONENT_DATA" | jq -r '.languages[]')
KONFLUX_COMPONENT=$(echo "$COMPONENT_DATA" | jq -r '.konflux_component // empty')
GO_MOD_PATH=$(echo "$COMPONENT_DATA" | jq -r '.go_mod_path // "."')
```

If the container is not in the mapping, ask the user for the repository URL.

### 4. Clone Repository and Check Package Presence

Clone the upstream repo (shallow clone to `/tmp`):

```bash
REPO_DIR="/tmp/assess-${UPSTREAM_REPO//\//__}"
if [ ! -d "$REPO_DIR" ]; then
  gh repo clone "$UPSTREAM_REPO" "$REPO_DIR" -- --depth=1
fi
cd "$REPO_DIR"

# Checkout the target branch
TARGET_GIT_BRANCH="redhat-${TARGET_BRANCH}"
git fetch origin "$TARGET_GIT_BRANCH" 2>/dev/null || \
  git fetch origin "master" 2>/dev/null
git checkout "$TARGET_GIT_BRANCH" 2>/dev/null || \
  git checkout "master"
```

**4.1: Check dependency manifests for the package**

```bash
# Python
grep -ri "${PACKAGE}" requirements*.txt setup.py pyproject.toml 2>/dev/null

# Go (check the correct go.mod path)
grep -i "${PACKAGE}" "${GO_MOD_PATH}/go.mod" 2>/dev/null

# Node.js
grep -i "${PACKAGE}" package.json web/package.json 2>/dev/null
```

**4.2: Extract installed version**

```bash
# Python — extract pinned version
INSTALLED_VERSION=$(grep -iE "^${PACKAGE}[=>~!]" requirements*.txt 2>/dev/null | \
  head -1 | grep -oP '[\d]+\.[\d]+[\d.]*')

# Go — extract from go.mod
INSTALLED_VERSION=$(grep -i "${PACKAGE}" "${GO_MOD_PATH}/go.mod" 2>/dev/null | \
  awk '{print $2}' | sed 's/^v//')

# Node.js — extract from package-lock.json
INSTALLED_VERSION=$(jq -r --arg pkg "$PACKAGE" \
  '.packages["node_modules/"+$pkg].version // .dependencies[$pkg].version // empty' \
  package-lock.json 2>/dev/null)
```

### 5. Classify the Fix Category

Run through the classification logic in order:

**5.1: Is it a Go stdlib CVE?**

If the package name starts with a Go stdlib path (e.g., `crypto/`, `net/`,
`encoding/`, `math/`, `os/`, `syscall/`), classify as `go-stdlib`:

```bash
if echo "$PACKAGE" | grep -qE '^(crypto|net|encoding|math|os|syscall|archive|compress|html|image|mime|path|regexp|text|unicode)/'; then
  VERDICT="go-stdlib"
fi
```

**5.2: Is the package in the dependency manifests?**

If the package was found in step 4.1:
- Compare installed version against the advisory's affected range
- If installed version is in the affected range → `package-bump`
- If installed version is already at or above the fixed version → `not-affected`
  (VEX: "Vulnerable Code not Present")

```bash
HIGHER=$(printf '%s\n' "$INSTALLED_VERSION" "$FIXED_VERSION" | sort -V | tail -1)
if [ "$HIGHER" = "$INSTALLED_VERSION" ] && [ "$INSTALLED_VERSION" != "$FIXED_VERSION" ]; then
  VERDICT="not-affected"
  VEX_JUSTIFICATION="Vulnerable Code not Present"
  VEX_EVIDENCE="Package ${PACKAGE} at version ${INSTALLED_VERSION} >= fixed version ${FIXED_VERSION}"
fi
```

**5.3: Is the package NOT in any manifest?**

If the package was not found in any dependency manifest:

a. Check the Containerfile for RPM/base-image references:

```bash
CONTAINERFILE="${KONFLUX_COMPONENT}Containerfile"
if [ -n "$KONFLUX_COMPONENT" ]; then
  # Check FROM lines and microdnf install lines
  grep -E "(FROM|microdnf.*install)" "$CONTAINERFILE" 2>/dev/null
fi
```

If the package comes from an RPM or base image → `rpm-layer`

b. If not in RPMs either → `not-affected` (VEX: "Component not Present")

**5.4: Symbol-level analysis (for ambiguous cases)**

When the package IS in the dependency tree but it's unclear whether the
vulnerable code path is exercised:

**Go — govulncheck call-graph analysis:**

```bash
cd "${GO_MOD_PATH}"
GO_VERSION=$(grep '^go ' go.mod | awk '{print $2}')
if [[ "$GO_VERSION" =~ ^[0-9]+\.[0-9]+$ ]]; then
  GO_VERSION="${GO_VERSION}.0"
fi

SCAN_OUTPUT=$(GOTOOLCHAIN="go${GO_VERSION}" govulncheck -show verbose ./... 2>&1)

# Check if CVE appears as "called" vs "informational"
if echo "$SCAN_OUTPUT" | grep -A5 "$CVE_ID" | grep -q "Informational"; then
  VERDICT="not-affected"
  VEX_JUSTIFICATION="Vulnerable Code not in Execute Path"
  VEX_EVIDENCE="govulncheck reports ${PACKAGE} as Informational — vulnerable symbol not called in code path"
elif echo "$SCAN_OUTPUT" | grep -q "$CVE_ID"; then
  VERDICT="package-bump"
else
  VERDICT="not-affected"
  VEX_JUSTIFICATION="Component not Present"
  VEX_EVIDENCE="govulncheck did not detect ${CVE_ID} in the project"
fi
```

**Python — import and function usage search:**

If the advisory lists specific affected functions, search for their usage:

```bash
# Search for imports of the affected module
grep -rn "import ${PACKAGE}" --include="*.py" . 2>/dev/null
grep -rn "from ${PACKAGE}" --include="*.py" . 2>/dev/null

# If advisory specifies affected functions, search for those
for FUNC in $AFFECTED_FUNCTIONS; do
  grep -rn "${FUNC}" --include="*.py" . 2>/dev/null
done
```

If no imports or affected function calls found → `not-affected`
(VEX: "Vulnerable Code not in Execute Path")

**Node.js — dependency tree and usage check:**

```bash
# Check if package is in the dependency tree
npm ls "${PACKAGE}" 2>/dev/null

# Search for usage of affected API in source
grep -rn "require.*${PACKAGE}" --include="*.js" --include="*.ts" . 2>/dev/null
grep -rn "from.*${PACKAGE}" --include="*.js" --include="*.ts" . 2>/dev/null
```

**5.5: Does the fix require code changes?**

If the advisory indicates breaking changes, removed APIs, or behavior
changes that require code modifications beyond a version bump:

- Check the package changelog/release notes for breaking changes
- If the fix introduces incompatible API changes → `code-change-required`

### 6. Write Assessment Artifact

Save to `artifacts/quay-cvefix/assess/CVE-YYYY-XXXXX.md`:

```bash
mkdir -p artifacts/quay-cvefix/assess
```

The artifact includes:

```markdown
# CVE Assessment: CVE-YYYY-XXXXX

## CVE Details
- **CVE ID**: CVE-YYYY-XXXXX
- **Severity**: HIGH (CVSS 7.5)
- **CWE**: CWE-400
- **Package**: urllib3
- **Affected versions**: < 2.3.0
- **Fixed version**: 2.3.0
- **Description**: ...

## Advisory Sources
- NVD: https://nvd.nist.gov/vuln/detail/CVE-YYYY-XXXXX
- GHSA: https://github.com/advisories/GHSA-XXXX-XXXX-XXXX
- Go Vuln DB: (if applicable)

## Impact Analysis
- **Container**: quay/quay-rhel9
- **Upstream repo**: quay/quay
- **Target branch**: redhat-3.17 [quay-3.17]
- **Package found in**: requirements.txt (version 2.2.1)
- **Version comparison**: 2.2.1 < 2.3.0 (affected)
- **Symbol analysis**: N/A (version check sufficient)

## Verdict
- **Category**: package-bump
- **Evidence**: urllib3==2.2.1 in requirements.txt, advisory affects < 2.3.0
- **Action**: Bump urllib3 to >= 2.3.0 in requirements.txt

## Confidence Assessment
- **Level**: high
- **Score**: 95
- **Score rationale**: Clear version match against advisory range
- **Open questions**: None
```

### 7. Post Jira Comment

Post a structured comment to the Jira ticket:

**For package-bump / go-stdlib:**

```text
[Phase: Assess] CVE Triage Complete

CVE: CVE-YYYY-XXXXX
Package: <package> (<current-version> -> <fixed-version>)
Component: <container-name>
Target Branch: <branch> [quay-X.Y]

Advisory: <severity> (CVSS X.X) - <brief description>
Sources: <CVE.org link>, <GHSA link if available>

Verdict: package-bump
Evidence: <1-2 sentences explaining the verdict>

Next: Applying fix.
```

**For not-affected (VEX):**

```text
[Phase: Assess] CVE Not Affected - VEX Justification

CVE: CVE-YYYY-XXXXX
Package: <package>
Component: <container-name>

VEX Justification: <justification type>
Evidence: <concrete evidence>

Scan Date: <ISO timestamp>
Repository: <org/repo>
Branch: <branch>

This issue can be closed as "Not a Bug / <justification>" if the above evidence is satisfactory.
```

**For rpm-layer:**

```text
[Phase: Assess] CVE in Base Image / RPM Layer

CVE: CVE-YYYY-XXXXX
Package: <package>
Component: <container-name>

Finding: Package <package> is not declared in application dependencies.
It is installed via <RPM / base image layer>.
Base Image: <image reference from Containerfile>
Source: <microdnf install line or FROM line>

This CVE cannot be fixed in the application repository.
The base image team needs to release an updated image.

Next: No PR created. Awaiting base image update.
```

### 8. Cleanup

Remove assessment clones from `/tmp` (unless the fix phase will reuse them):

```bash
# Only clean up if the verdict is not package-bump or go-stdlib
if [ "$VERDICT" != "package-bump" ] && [ "$VERDICT" != "go-stdlib" ]; then
  rm -rf "$REPO_DIR"
fi
```

## Output

- `artifacts/quay-cvefix/assess/CVE-YYYY-XXXXX.md` — per-CVE assessment
- Jira comment posted to the ticket
- Verdict returned to the controller for routing

## Success Criteria

- [ ] Advisory data gathered from at least one source (NVD, GHSA, or Jira description)
- [ ] Package presence checked in dependency manifests
- [ ] Version comparison performed against advisory range
- [ ] Symbol analysis performed for ambiguous cases
- [ ] Verdict assigned with concrete evidence
- [ ] Assessment artifact saved
- [ ] Jira comment posted
