---
name: fix-node
description: >
  Apply a Node.js dependency CVE fix via lockfile-only updates. Supports npm
  and pnpm. Uses overrides only as fallback when direct update is insufficient.
allowed-tools:
  - Bash(npm *)
  - Bash(npx *)
  - Bash(pnpm *)
  - Bash(corepack *)
  - Bash(python3 "${CLAUDE_PLUGIN_ROOT}/scripts/patch-pnpm-lock.py" *)
  - Bash(jq *)
  - Bash(grep *)
  - Bash(sed *)
  - Bash(cat *)
  - Read
  - Write
  - Edit
  - Glob
  - Grep
---

# Fix Node.js CVE

## Inputs

| Input | Required |
|-------|----------|
| `PACKAGE` | yes |
| `FIXED_VERSION` | yes |
| `CVE_ID` | yes |
| `REPO_DIR` | yes (cwd) |
| `NODEJS_DIRS` | default `.` `web/` |
| `USE_PNPM_WEB` | default false — set true when web/ uses pnpm |
| `PNPM_VERSION` | default `10` — CI pnpm major version |

## Strategy

1. Direct lockfile update first (sufficient for most transitive CVEs)
2. Overrides in `package.json` only when update cannot reach fixed version
3. Verify lockfile shows `package@<FIXED_VERSION>` before commit
4. Do not commit `package.json` unless overrides were required

## Steps

### 1. Update each directory

For each dir in `NODEJS_DIRS` with a `package.json`:

```bash
cd "${DIR}"

if [ "$USE_PNPM_WEB" = true ] && [ "$DIR" = "web/" ]; then
  corepack prepare "pnpm@${PNPM_VERSION}" --activate
  rm -rf node_modules
  pnpm update "${PACKAGE}@${FIXED_VERSION}" --lockfile-only 2>/dev/null || \
    pnpm update "${PACKAGE}" --lockfile-only 2>/dev/null || true
  npm update "${PACKAGE}" --package-lock-only 2>/dev/null || true
  # Fallback if lockfile-only update did not reach FIXED_VERSION:
  # python3 "${CLAUDE_PLUGIN_ROOT}/scripts/patch-pnpm-lock.py" web/pnpm-lock.yaml "$PACKAGE" "$OLD" "$FIXED"
  # Validate CI will accept the lockfile (do not use this to apply the bump):
  pnpm install --frozen-lockfile
else
  npm update "${PACKAGE}@${FIXED_VERSION}" 2>/dev/null || npm update "${PACKAGE}" 2>/dev/null || true
fi

cd "$REPO_DIR"
```

### 2. Override fallback

If lockfile version is still below `FIXED_VERSION`:

```bash
jq --arg pkg "$PACKAGE" --arg ver "${FIXED_VERSION}" \
  '.overrides[$pkg] = $ver | .pnpm.overrides[$pkg] = $ver' package.json > package.json.tmp && \
  mv package.json.tmp package.json
pnpm install --no-frozen-lockfile
```

For npm-only directories (no pnpm), use `.overrides` only and run
`npm install`.

### 3. Verify

```bash
npm audit 2>/dev/null | grep -i "${CVE_ID}" && echo "WARNING" || echo "CVE resolved"
# For pnpm web/:
grep -E "  ${PACKAGE}@" pnpm-lock.yaml | head -3
grep -q '^overrides:' pnpm-lock.yaml || { echo "ERROR: missing overrides: header"; exit 1; }
```

## Output

Modified lockfiles in the specified directories. `package.json` only if overrides added.
