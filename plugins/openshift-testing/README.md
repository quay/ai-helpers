# openshift-testing

OpenShift cluster provisioning and remote Playwright browser deployment for
E2E testing workflows.

## Skills

| Skill | Purpose |
|-------|---------|
| `/openshift-testing:cluster-provision` | Provision ephemeral OpenShift cluster via Gangway API |
| `/openshift-testing:remote-playwright` | Deploy Playwright browser server on cluster |

## Scripts

| Script | Purpose |
|--------|---------|
| `cluster-provision.sh` | Cluster lifecycle: up, down, status |
| `remote-playwright.sh` | Playwright server lifecycle: up, down, status |

## Prerequisites

- `GANGWAY_TOKEN` — OpenShift CI auth token
- `KUBECONFIG_ENCRYPTION_KEY` — Kubeconfig decryption passphrase
- `oc` CLI (auto-installed if missing)

## Configuration

| Variable | Default | Purpose |
|----------|---------|---------|
| `GANGWAY_BASE` | OpenShift CI Gangway URL | Gangway API base URL |
| `GANGWAY_JOB_NAME` | `periodic-ci-quay-quay-master-claim-claim-cluster` | ProwJob name |
