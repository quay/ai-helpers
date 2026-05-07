# Quay Deploy — Konflux FBC to Ephemeral Cluster

Automated deployment and validation of Quay release candidates from Konflux FBC
(File-Based Catalog) builds onto ephemeral OpenShift clusters.

## Why

Deploying a Quay RC from Konflux involves 8+ manual steps: claiming a cluster,
merging pull secrets, applying ICSP/IDMS for pre-release image mirroring,
installing object storage, creating OLM catalogs/subscriptions, waiting for
everything to reconcile, and then manually testing the UI. This workflow
automates all of them — including frontend validation with Playwright.

## Usage

```bash
# Full autonomous deployment + UI validation
/deploy image-rbac-proxy.apps.stone-prd-rh01.pg1f.p1.openshiftapps.com/redhat-user-workloads/quay-eng-tenant/stable-3-18-v4-21@sha256:abc123...

# Deploy + black-box test a specific feature
/deploy image-rbac-proxy.apps.stone-prd-rh01.pg1f.p1.openshiftapps.com/.../stable-3-18-v4-21@sha256:abc... --feature PROJQUAY-1234
/deploy image-rbac-proxy.apps.stone-prd-rh01.pg1f.p1.openshiftapps.com/.../stable-3-18-v4-21@sha256:abc... --feature ./feature-spec.md

# Explicit channel and OCP version
/deploy image-rbac-proxy.apps.stone-prd-rh01.pg1f.p1.openshiftapps.com/.../stable-3-18-v4-21@sha256:abc... --channel stable-3.18 --ocp-version 4.18

# Manual mode (pause after each state for review)
/deploy image-rbac-proxy.apps.stone-prd-rh01.pg1f.p1.openshiftapps.com/.../stable-3-18-v4-21@sha256:abc... --manual
```

## State Machine

```text
PROVISION ──→ CONFIGURE_PULL_SECRETS ──→ APPLY_MIRRORS ──→ WAIT_MCP
                                                              │
                                                              ▼
INSTALL_STORAGE ◄─────────────────────────────────────────────┘
      │
      ▼
INSTALL_CATALOG ──→ SUBSCRIBE ──→ WAIT_OPERATOR ──→ DEPLOY_QUAY
                                                        │
                                                        ▼
                                                   WAIT_QUAY
                                                        │
                                                        ▼
                                                     VERIFY
                                                        │
                                                        ▼
                                                  VALIDATE_UI
                                                        │
                                          ┌─────────────┤
                                          ▼             ▼
                                  VALIDATE_FEATURE   COMPLETE
                                  (if --feature)        ▲
                                          │             │
                                          └─────────────┘
```

## States

| State | Description |
|-------|-------------|
| PROVISION | Claim ephemeral OpenShift cluster via Gangway API |
| CONFIGURE_PULL_SECRETS | Merge Konflux registry credentials into cluster global pull secret |
| APPLY_MIRRORS | Apply IDMS (OCP 4.14+) or ICSP for Konflux pre-release image mirroring |
| WAIT_MCP | Wait for MachineConfigPools to stabilize after mirror config |
| INSTALL_STORAGE | Deploy NooBaa via ODF operator for S3-compatible object storage |
| INSTALL_CATALOG | Create OLM CatalogSource pointing to Konflux FBC image |
| SUBSCRIBE | Create Subscription for quay-operator from the FBC catalog |
| WAIT_OPERATOR | Poll until quay-operator CSV reaches Succeeded phase |
| DEPLOY_QUAY | Create QuayRegistry custom resource |
| WAIT_QUAY | Poll until QuayRegistry reports Available |
| VERIFY | Run health checks (route, `/health/instance`, login page) |
| VALIDATE_UI | Deploy Playwright browser, login, smoke test key pages with video recording |
| VALIDATE_FEATURE | Black-box test a specific feature via Playwright (conditional) |
| COMPLETE | Print summary with cluster details, artifacts, and bug reports |

## Prerequisites

### Environment Variables

| Variable | How to get it |
|----------|---------------|
| `GANGWAY_TOKEN` | `oc login https://api.ci.l2s4.p1.openshiftapps.com:6443 --web && export GANGWAY_TOKEN=$(oc whoami -t)` |
| `KUBECONFIG_ENCRYPTION_KEY` | Contact Quay CI team for the decryption passphrase |
| `KONFLUX_IMAGE_PULL_TOKEN` | Bearer token for `image-rbac-proxy.apps.stone-prd-rh01.pg1f.p1.openshiftapps.com` (see [Konflux Image RBAC Proxy](https://github.com/konflux-ci/image-controller) for provisioning) |

### Plugin Dependencies

This workflow depends on the `openshift-testing` plugin (for `cluster-provision.sh`
and `remote-playwright.sh`). These are installed automatically at session start
via [Lola](https://github.com/RedHatProductSecurity/lola) from `.lola-req`.

### CLI Tools

- `oc` — OpenShift CLI (auto-installed by cluster-provision.sh if missing)
- `jq` — JSON processor
- `curl` — HTTP client
- `openssl` — For kubeconfig decryption
- `npx` — For Playwright CLI (Node.js required)

## State Persistence

Deploy state files live at `.claude/deploy-state/<DEPLOY_ID>.json`. They
survive context compaction and enable mid-pipeline resume. Each deployment
gets a unique ID derived from the FBC image digest.

## Artifacts

All screenshots and video recordings are saved to `/tmp/quay-validate/`:
- `login-page.png` — Login page screenshot
- `smoke-test.webm` — Video of smoke test walkthrough
- `bug-N.png` — Screenshot at bug detection point
- `feature-test-N.webm` — Video of feature test steps

**Videos of bugs are the primary deliverable for human review.**
