# Quay CVE Fix Workflow

## Safety

- No direct commits to main/master or release branches
- No force-push
- No secret/token logging
- No skipping CI or pre-commit hooks
- Separate PR per CVE per repo — never combine multiple CVE fixes
- Clone repositories only to `/tmp` — never to the user's workspace
- Clean up `/tmp` clones after workflow completes
- Never run `rm -rf` on paths outside `/tmp`

## Mandatory Assessment Gate

- **Always run the assess skill before the fix skill** — never skip triage
- **Never blindly bump a package** without consulting advisory data first
- Read the Jira ticket description AND linked advisories (CVE.org, GHSA)
- Check affected version ranges against what the repo actually uses
- For ambiguous cases, perform symbol-level analysis before deciding

## Fix Category Rules

| Category | Action | PR Created? |
|----------|--------|-------------|
| `package-bump` | Apply version bump, run tests, create PR | Yes |
| `go-stdlib` | Bump go-toolset in quay-konflux-components | Yes |
| `rpm-layer` | Post Jira comment, document, skip | No |
| `code-change-required` | Escalate to user | No |
| `not-affected` | Post VEX justification to Jira, skip | No |

- **Never attempt to fix RPM-layer CVEs** in application repositories
- **Never attempt complex code refactors** — escalate to the team
- **VEX justifications must include concrete evidence** (govulncheck output, import search, version comparison)

## Branch Cascade

- If `[quay-X.Y]` in the Jira summary indicates a release branch, the fix
  MUST exist on master first (or be applied there first)
- If the target is `3.17`, fix on master first, then backport to `redhat-3.17`
- Never fix a lower branch without the fix existing on upper branches
- Branches `3.11` and `3.13` are EOL — skip or warn, do not fix
- Each branch gets its own separate PR — never combine branches

## Quay-Specific Fix Conventions

### Python (quay/quay only)
- Bump in `requirements.txt` or `requirements-dev.txt`
- Regenerate `requirements-build.txt` using `pybuild-deps`
- Remove setuptools==82 entries from `requirements-build.txt` (known bug)

### Go (all Go repos)
- `go get <pkg>@<version>` + `go mod tidy`
- For `quay/quay`: go.mod is in `config-tool/` directory, not root

### Go stdlib (via quay-konflux-components)
- Bump the `go-toolset` image tag in the component's `Containerfile`
- Pattern: `FROM registry.access.redhat.com/ubi9/go-toolset:<tag>`
- PR targets `quay/quay-konflux-components`, not the upstream repo

### Node.js (quay/quay only)
- `npm update <package>` or npm `overrides` as fallback
- Lockfiles at: root `package-lock.json`, `web/package-lock.json`
- Branches <= 3.16: also `config-tool/pkg/lib/editor/package-lock.json`

## Jira Comments

Post structured comments to Jira at each phase using
`jira-ops.sh comment <TICKET_KEY> "<text>"`. Use the `[Phase: <name>]`
prefix format for consistency with other Quay workflows.

## Duplicate Prevention

- Always check for existing open PRs before creating new ones
- Search by CVE ID and by package name (catches Dependabot/Renovate PRs)
- Use `gh pr list --state open --base <branch> --search "<term>"`

## Commit Format

```text
fix(cve): CVE-YYYY-XXXXX - <package-name> (<PROJQUAY-XXXX>)

- Update <package> from X.X.X to Y.Y.Y
- Addresses vulnerability in <component>

Resolves: PROJQUAY-XXXX
```

## PR Description

Every PR must include:
1. CVE details — ID, severity, CVSS, affected/fixed versions
2. Fix summary — what changed and why
3. Test results — status, command, output (even if failed)
4. Jira references — PROJQUAY-XXXX issue IDs
5. Assessment summary — link to assess artifact
