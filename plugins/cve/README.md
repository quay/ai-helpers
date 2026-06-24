# CVE Plugin

Generic CVE triage and dependency-bump automation for Claude Code workflows.

## Skills

| Skill | Purpose |
|-------|---------|
| `/cve:assess` | Fetch advisories (NVD, GHSA, Go vuln DB), check package presence, classify verdict |
| `/cve:fix-python` | Bump Python requirements, regenerate lockfiles, verify with pip-audit |
| `/cve:fix-go` | `go get` + `go mod tidy` + govulncheck verification |
| `/cve:fix-node` | Lockfile-only npm/pnpm updates with override fallback |

## Scripts

| Script | Purpose |
|--------|---------|
| `cve-fetch-nvd.sh` | Query NVD API for a CVE ID |
| `cve-fetch-ghsa.sh` | Query GitHub Security Advisory by CVE or GHSA ID |
| `cve-fetch-go-vuln.sh` | Query Go vulnerability database |
| `cve-compare-versions.sh` | Compare semver strings (affected vs fixed) |
| `cve-check-existing-pr.sh` | Detect open PRs for a CVE or package |
| `patch-pnpm-lock.py` | Patch a package version in pnpm-lock.yaml |

## Configuration

Set via environment variables (see [enhancement 003](../../enhancements/003-cve-plugin-extraction.md)):

| Variable | Default |
|----------|---------|
| `CVE_ARTIFACT_DIR` | `artifacts/cve/assess` |
| `CVE_FIX_ARTIFACT_DIR` | `artifacts/cve/fixes` |
| `CVE_CLONE_ROOT` | `/tmp` |
| `CVE_BRANCH_PREFIX` | _(empty)_ |
| `CVE_DEFAULT_BRANCH` | `master` |

## Installation

```bash
uvx --python 3.13 --from lola-ai lola mod add https://github.com/quay/ai-helpers.git --module-content=plugins/cve
lola install cve -a claude-code ./my-project
```

Or declare in `.lola-req`:

```text
https://github.com/quay/ai-helpers.git --module-content=plugins/cve
```

## Workflow integration

Project workflows (e.g. `workflows/quay-cvefix`) provide thin wrapper skills
that set project-specific mappings and policies, then delegate to these
generic skills.
