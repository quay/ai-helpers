---
name: konflux
description: >
  Interact with the Konflux build cluster. Check pipeline status, view build
  logs, list components and applications, debug failures. Requires
  KONFLUX_KUBECONFIG_DATA env var (decoded at session start).
argument-hint: "<command> [args...]  — builds|status|logs|tasklog|components|apps|snapshots"
allowed-tools:
  - Bash(bash .claude/scripts/konflux.sh *)
  - Bash(oc --kubeconfig=/tmp/konflux-kubeconfig *)
  - Read
---

# Konflux Build Cluster

Interact with the Konflux build cluster to check builds, view logs, and debug pipeline failures.

## Arguments

Parse `$ARGUMENTS` to determine the subcommand and its arguments.

Available subcommands:
- `builds [NAMESPACE] [COMPONENT]` — List recent PipelineRuns
- `status <PIPELINERUN> [NAMESPACE]` — Detailed PipelineRun status with TaskRun breakdown
- `logs <PIPELINERUN> [NAMESPACE]` — Logs from failed TaskRuns (or last TaskRun if all passed)
- `tasklog <TASKRUN> [NAMESPACE]` — Logs from a specific TaskRun pod
- `components [NAMESPACE]` — List Components with git repos
- `apps [NAMESPACE]` — List Applications
- `snapshots [NAMESPACE]` — List recent Snapshots

Default namespace: `quay-eng-tenant`. Override with `KONFLUX_DEFAULT_NS` env var.

If no subcommand is given or the user's intent is ambiguous, start with `builds` to show recent pipeline activity.

## Step 1: Run the command

```bash
bash .claude/scripts/konflux.sh <subcommand> [args...]
```

## Step 2: Interpret and follow up

After running the command, interpret the output for the user:

- **builds**: Highlight any failed or running PipelineRuns. Offer to show `status` or `logs` for specific runs.
- **status**: Identify which TaskRun failed and suggest viewing its logs.
- **logs**: Summarize the error. If it's a build failure, check if it's a code issue or infra flake.
- **components**: Show which repos/branches are configured for builds.

## Step 3: Direct oc commands

For operations not covered by the script, use `oc` directly:

```bash
oc --kubeconfig=/tmp/konflux-kubeconfig get <resource> -n <namespace> [flags]
```

Common resources: `pipelineruns`, `taskruns`, `components`, `applications`, `snapshots`, `integrationtestscenarios`.

## Troubleshooting

| Error | Fix |
|-------|-----|
| `Kubeconfig not found` | Ensure `KONFLUX_KUBECONFIG_DATA` env var is set. Re-run session setup. |
| `oc not found` | Run: session-setup.sh to install oc |
| `Forbidden` | Kubeconfig may lack permissions for that namespace |
| `No resources found` | Check the namespace and resource type |
