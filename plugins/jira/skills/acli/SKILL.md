---
name: acli
description: "Reference for using the acli (Atlassian CLI) to interact with JIRA issues. Covers searching with JQL, creating, viewing, editing, transitioning, assigning, commenting, linking, cloning, and bulk operations. Use when performing any JIRA issue operation via acli from the command line. Provides patterns for output parsing with jq, ADF-formatted descriptions and comments, custom field handling via REST fallback, and bulk JQL-targeted mutations."
allowed-tools:
  - Bash(acli jira workitem view *)
  - Bash(acli jira workitem search *)
  - Bash(acli jira workitem create *)
  - Bash(acli jira workitem create-bulk *)
  - Bash(acli jira workitem edit *)
  - Bash(acli jira workitem transition *)
  - Bash(acli jira workitem assign *)
  - Bash(acli jira workitem clone *)
  - Bash(acli jira workitem comment *)
  - Bash(acli jira workitem link *)
  - Bash(acli jira project *)
  - Bash(acli jira auth status)
  - Bash(curl -sS -u * https://*.atlassian.net/rest/api/3/*)
  - Bash(jq *)
  - Read
---

# acli JIRA Operations

The `acli` CLI is the primary interface for JIRA issue operations. General syntax:

```
acli jira <resource> <action> [flags]
```

For the full flag reference of every command, read `references/command-ref.md`.

## Authentication

Check auth status before any operation:

```bash
acli jira auth status
```

If not authenticated:

```bash
acli jira auth login --site <domain> --email <email> --token
```

Credential locations (checked in order):
- `~/.config/acli/jira_config.yaml` — email
- `~/.config/acli/token.txt` or `~/.acli-token` — API token
- `$JIRA_API_TOKEN` / `$JIRA_USER` — environment variables

## Viewing Issues

```bash
acli jira workitem view KEY-123
acli jira workitem view KEY-123 --json
acli jira workitem view KEY-123 --fields '*all' --json
acli jira workitem view KEY-123 --fields 'summary,status,assignee'
```

Parse JSON output with `jq`:

```bash
acli jira workitem view KEY-123 --json | jq '{
  key: .key,
  summary: .fields.summary,
  status: .fields.status.name,
  assignee: (.fields.assignee.displayName // "unassigned"),
  type: .fields.issuetype.name,
  priority: .fields.priority.name,
  labels: .fields.labels
}'
```

## Searching with JQL

```bash
acli jira workitem search --jql "project = PROJ AND status = 'In Progress'" --json
acli jira workitem search --jql "assignee = currentUser()" --fields "key,summary,status" --csv
acli jira workitem search --jql "project = PROJ" --count
acli jira workitem search --jql "project = PROJ" --limit 50 --json
acli jira workitem search --jql "project = PROJ" --paginate
```

Common JQL patterns:

| Query | JQL |
|---|---|
| My open issues | `assignee = currentUser() AND status != Done` |
| Recent bugs | `project = PROJ AND type = Bug AND created >= -7d` |
| Unassigned in project | `project = PROJ AND assignee is EMPTY` |
| By label | `project = PROJ AND labels = "my-label"` |
| By component | `project = PROJ AND component = "my-component"` |
| Text search | `project = PROJ AND text ~ "search term"` |
| By priority | `project = PROJ AND priority in (Critical, Blocker)` |
| Updated recently | `project = PROJ AND updated >= -1d ORDER BY updated DESC` |

Parse search results:

```bash
acli jira workitem search --jql "..." --json | jq '[.[] | {key, summary: .fields.summary, status: .fields.status.name}]'
```

## Creating Issues

Basic creation:

```bash
acli jira workitem create \
  --project "PROJ" --type "Bug" \
  --summary "Summary text" \
  --description "Description text" \
  --assignee "@me" \
  --label "label1,label2" \
  --json
```

For custom fields (components, priority, epic link), use `--from-json`:

```bash
acli jira workitem create --from-json issue.json --json
```

Build the JSON with `jq`:

```bash
jq -n '{
  projectKey: "PROJ",
  issueType: "Story",
  summary: "My story",
  description: "Description in plain text or ADF",
  assignee: "user@example.com",
  label: ["label1"],
  additionalAttributes: {
    components: [{"name": "my-component"}],
    priority: {"name": "Major"},
    parent: {"key": "PROJ-100"}
  }
}' > /tmp/issue.json
acli jira workitem create --from-json /tmp/issue.json --json
```

Set fields that `create` cannot handle natively via REST after creation — see the Custom Fields section below.

### Bulk Creation

From JSON:

```bash
acli jira workitem create-bulk --from-json issues.json --yes
```

From CSV (columns: summary, projectKey, issueType, description, label, parentIssueId, assignee):

```bash
acli jira workitem create-bulk --from-csv issues.csv --yes
```

Generate example JSON structure:

```bash
acli jira workitem create-bulk --generate-json
```

## Editing Issues

Direct field edits:

```bash
acli jira workitem edit --key KEY-123 --summary "New summary" --yes
acli jira workitem edit --key KEY-123 --description "New description" --yes
acli jira workitem edit --key KEY-123 --assignee "user@example.com" --yes
acli jira workitem edit --key KEY-123 --labels "new-label" --yes
acli jira workitem edit --key KEY-123 --type "Story" --yes
```

Bulk edit via JQL:

```bash
acli jira workitem edit --jql "project = PROJ AND labels = old-label" --labels "new-label" --yes
```

Remove labels:

```bash
acli jira workitem edit --key KEY-123 --remove-labels "unwanted-label" --yes
```

## Transitioning Issues

```bash
acli jira workitem transition --key KEY-123 --status "In Progress" --yes
```

Bulk transition via JQL:

```bash
acli jira workitem transition --jql "project = PROJ AND status = New" --status "In Progress" --yes
```

If a transition fails, view the issue with `--fields '*all' --json` and inspect available transitions.

## Assigning Issues

```bash
acli jira workitem assign --key KEY-123 --assignee "@me"
acli jira workitem assign --key KEY-123 --assignee "user@example.com"
acli jira workitem assign --key KEY-123 --remove-assignee
```

Bulk assign via JQL:

```bash
acli jira workitem assign --jql "project = PROJ AND status = New" --assignee "@me" --yes
```

## Comments

Create a comment:

```bash
acli jira workitem comment create --key KEY-123 --body "Comment text"
```

Create from file (supports ADF JSON):

```bash
acli jira workitem comment create --key KEY-123 --body-file comment.json
```

List comments:

```bash
acli jira workitem comment list --key KEY-123 --json
```

Update last comment:

```bash
acli jira workitem comment create --key KEY-123 --body "Updated text" --edit-last
```

### ADF Format for Comments and Descriptions

JIRA Cloud uses Atlassian Document Format (ADF) for rich text. When providing structured content to `--description`, `--body`, or `--description-file`/`--body-file`, use ADF JSON:

```json
{
  "type": "doc",
  "version": 1,
  "content": [
    {
      "type": "paragraph",
      "content": [
        {"type": "text", "text": "Plain text here"}
      ]
    },
    {
      "type": "heading",
      "attrs": {"level": 3},
      "content": [
        {"type": "text", "text": "Section Heading"}
      ]
    },
    {
      "type": "bulletList",
      "content": [
        {
          "type": "listItem",
          "content": [
            {
              "type": "paragraph",
              "content": [{"type": "text", "text": "Item one"}]
            }
          ]
        }
      ]
    },
    {
      "type": "codeBlock",
      "attrs": {"language": "bash"},
      "content": [
        {"type": "text", "text": "echo hello"}
      ]
    }
  ]
}
```

Always prefer ADF JSON over wiki markup for descriptions and comments.

## Linking Issues

List available link types:

```bash
acli jira workitem link type
```

Create a link:

```bash
acli jira workitem link create --out KEY-123 --in KEY-456 --type "Blocks"
```

- `--out` is the outward issue (e.g., "blocks" KEY-456)
- `--in` is the inward issue (e.g., "is blocked by" KEY-123)

List links on an issue:

```bash
acli jira workitem link list --key KEY-123
```

Bulk link from CSV:

```bash
acli jira workitem link create --from-csv links.csv --yes
```

## Cloning Issues

```bash
acli jira workitem clone --key KEY-123 --to-project "OTHERPROJ" --yes
```

Clone and link:

```bash
CLONE_KEY=$(acli jira workitem clone --key KEY-123 --to-project PROJ --yes --json | jq -r '.key')
acli jira workitem link create --out "$CLONE_KEY" --in KEY-123 --type "Blocks" --yes
```

## Custom Fields via REST Fallback

`acli workitem edit` does not support custom fields. Use the REST API with curl for fields like components, priority, fix versions, or any custom field:

Obtain `EMAIL` and `TOKEN` from the environment (`$JIRA_USER`, `$JIRA_API_TOKEN`) or by reading `~/.config/acli/jira_config.yaml` and `~/.config/acli/token.txt` with the Read tool.

```bash
DOMAIN="${JIRA_DOMAIN:-redhat.atlassian.net}"

curl -sS -u "$EMAIL:$TOKEN" -X PUT -H "Content-Type: application/json" \
  -d '{"fields":{"components":[{"name":"my-component"}],"priority":{"name":"Major"}}}' \
  "https://${DOMAIN}/rest/api/3/issue/KEY-123"
```

Build payloads dynamically with `jq`:

```bash
jq -n --arg ver "4.18" --arg field "customfield_10855" \
  '{fields: {($field): [{"name": $ver}]}}' | \
  curl -sS -u "$EMAIL:$TOKEN" -X PUT -H "Content-Type: application/json" -d @- \
  "https://${DOMAIN}/rest/api/3/issue/KEY-123"
```

## Output Handling

| Flag | Format | Best for |
|---|---|---|
| (none) | Human-readable table | Interactive use |
| `--json` | JSON | Parsing with `jq`, programmatic use |
| `--csv` | CSV | Spreadsheet export, bulk analysis |
| `--fields` | Select columns | Reducing noise in output |
| `--count` | Number only | Quick counts from search |

Combine `--json` with `jq` for precise extraction:

```bash
acli jira workitem search --jql "..." --json | jq '[.[] | {key, summary: .fields.summary}]'
```

## Project Listing

```bash
acli jira project list
acli jira project view PROJ
```

## Gotchas

- **Always use `--json`** — table/text output has known formatting bugs; `--json` is reliable
- **Always use `--yes`** in non-interactive contexts — acli prompts for confirmation by default
- **Intermittent failures** — acli can fail with "unexpected error" and a trace id; retry the command
- **`--fields` unreliable with custom fields** — use `'*all'` and filter with `jq` instead
- **`key = PROJ-123` in JQL can fail** — use `workitem view` for single-issue lookups
- **`--paginate` overrides `--limit`** — do not combine them
- **OAuth may not work in headless environments** — use API token auth instead

## Customer Data

Never include customer names, company names, or identifying information in issue descriptions, comments, or summaries. Generalize customer-specific details.
