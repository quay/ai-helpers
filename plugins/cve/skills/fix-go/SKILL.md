---
name: fix-go
description: >
  Apply a Go dependency CVE fix: go get, go mod tidy, verify with govulncheck.
allowed-tools:
  - Bash(go *)
  - Bash(govulncheck *)
  - Bash(grep *)
  - Bash(cat *)
  - Read
  - Write
  - Edit
  - Glob
  - Grep
---

# Fix Go Dependency CVE

## Inputs

| Input | Required |
|-------|----------|
| `PACKAGE` | yes |
| `FIXED_VERSION` | yes |
| `CVE_ID` | yes |
| `GO_MOD_PATH` | default `.` |
| `REPO_DIR` | yes (cwd) |

## Steps

### 1. Update dependency

```bash
cd "${GO_MOD_PATH}"
go get "${PACKAGE}@v${FIXED_VERSION}"
go mod tidy
```

### 2. Verify with govulncheck

```bash
GO_VERSION=$(grep '^go ' go.mod | awk '{print $2}')
if [[ "$GO_VERSION" =~ ^[0-9]+\.[0-9]+$ ]]; then
  GO_VERSION="${GO_VERSION}.0"
fi

SCAN_OUTPUT=$(GOTOOLCHAIN="go${GO_VERSION}" govulncheck -show verbose ./... 2>&1)

if echo "$SCAN_OUTPUT" | grep -q "$CVE_ID"; then
  echo "WARNING: CVE still detected after fix"
else
  echo "CVE resolved"
fi
```

## Output

Modified `go.mod` and `go.sum` in `${GO_MOD_PATH}`.
