# Konflux Plugin

Interact with the Konflux build cluster to check pipeline status, view build logs, list components, and debug failures.

## Prerequisites

- `KONFLUX_KUBECONFIG_DATA` environment variable set with base64-encoded kubeconfig
- Session setup decodes this to `/tmp/konflux-kubeconfig` automatically

## Skill: `/konflux`

```
/konflux builds                          # List recent PipelineRuns in quay-eng-tenant
/konflux builds quay-eng-tenant quay-py3 # Filter by component
/konflux status <pipelinerun-name>       # Detailed status with TaskRun breakdown
/konflux logs <pipelinerun-name>         # View logs from failed tasks
/konflux components                      # List configured components
/konflux apps                            # List applications
/konflux snapshots                       # List recent snapshots
```
