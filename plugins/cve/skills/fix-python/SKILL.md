---
name: fix-python
description: >
  Apply a Python dependency CVE fix: bump requirements pin, regenerate
  requirements-build.txt with pybuild-deps, verify with pip-audit.
allowed-tools:
  - Bash(pybuild-deps *)
  - Bash(pip-audit *)
  - Bash(pip *)
  - Bash(pip3 *)
  - Bash(sed *)
  - Bash(grep *)
  - Bash(cat *)
  - Read
  - Write
  - Edit
  - Glob
  - Grep
---

# Fix Python CVE

## Inputs

| Input | Required |
|-------|----------|
| `PACKAGE` | yes |
| `FIXED_VERSION` | yes |
| `CVE_ID` | yes |
| `REPO_DIR` | yes (cwd) |
| `CVE_PYBUILD_SETUPTOOLS_WORKAROUND` | optional, default false |

## Steps

### 1. Find requirements file

```bash
REQ_FILE=""
for f in requirements.txt requirements-dev.txt; do
  if grep -qi "^${PACKAGE}" "$f" 2>/dev/null; then
    REQ_FILE="$f"
    break
  fi
done
```

### 2. Bump version pin

```bash
ESCAPED_PACKAGE=$(printf '%s\n' "$PACKAGE" | sed 's/[.[\*^$]/\\&/g')
sed -i "s/^${ESCAPED_PACKAGE}[=>~!][=<>~!]*.*$/${PACKAGE}>=${FIXED_VERSION}/" "$REQ_FILE"
```

### 3. Regenerate requirements-build.txt

```bash
pybuild-deps compile --generate-hashes --output-file=requirements-build.txt requirements.txt

if [ "${CVE_PYBUILD_SETUPTOOLS_WORKAROUND:-false}" = "true" ]; then
  sed -i '/^setuptools==82\b/d' requirements-build.txt
fi
```

### 4. Verify

```bash
grep "${PACKAGE}" requirements-build.txt
pip-audit -r requirements.txt 2>/dev/null | grep -i "${CVE_ID}" && \
  echo "WARNING: CVE still detected" || echo "CVE resolved in scan"
```

## Output

Modified `requirements*.txt` and `requirements-build.txt` in `REPO_DIR`.
