# acli jira Command Reference

Complete flag reference for issue-related `acli jira` commands.

## workitem view

View issue details.

```
acli jira workitem view [key] [flags]
```

| Flag | Short | Description |
|---|---|---|
| `--fields` | `-f` | Comma-separated field list. `*all` = all fields, `*navigable` = navigable fields. Prefix with `-` to exclude. Default: `key,issuetype,summary,status,assignee,description` |
| `--json` | | JSON output |
| `--web` | `-w` | Open in browser |

## workitem search

Search issues via JQL.

```
acli jira workitem search [flags]
```

| Flag | Short | Description |
|---|---|---|
| `--jql` | `-j` | JQL query string |
| `--filter` | | Saved filter ID |
| `--fields` | `-f` | Comma-separated fields. Default: `issuetype,key,assignee,priority,status,summary` |
| `--json` | | JSON output |
| `--csv` | | CSV output |
| `--count` | | Return count only |
| `--limit` | `-l` | Max results |
| `--paginate` | | Fetch all pages (overrides `--limit`) |
| `--web` | `-w` | Open in browser |

## workitem create

Create a new issue.

```
acli jira workitem create [flags]
```

| Flag | Short | Description |
|---|---|---|
| `--project` | `-p` | Project key (required) |
| `--type` | `-t` | Issue type: Epic, Story, Task, Bug, etc. (required) |
| `--summary` | `-s` | Issue summary (required) |
| `--description` | `-d` | Plain text or ADF description |
| `--description-file` | | Read description from file |
| `--assignee` | `-a` | Email, account ID, `@me`, or `default` |
| `--label` | `-l` | Comma-separated labels |
| `--parent` | | Parent issue key (for subtasks or stories under epics) |
| `--from-file` | `-f` | Read summary/description from file |
| `--from-json` | | Full issue definition from JSON (supports `additionalAttributes` for custom fields) |
| `--generate-json` | | Print JSON template |
| `--editor` | `-e` | Open text editor |
| `--json` | | JSON output |

## workitem create-bulk

Bulk create issues.

```
acli jira workitem create-bulk [flags]
```

| Flag | Description |
|---|---|
| `--from-json` | JSON file with array of issue objects |
| `--from-csv` | CSV file (columns: summary, projectKey, issueType, description, label, parentIssueId, assignee) |
| `--generate-json` | Print JSON template |
| `--ignore-errors` | Continue past failures |
| `--yes` | Skip confirmation |

## workitem edit

Edit one or more issues.

```
acli jira workitem edit [flags]
```

**Targeting (pick one):**

| Flag | Short | Description |
|---|---|---|
| `--key` | `-k` | Comma-separated issue keys |
| `--jql` | | JQL query |
| `--filter` | | Saved filter ID |

**Field updates:**

| Flag | Short | Description |
|---|---|---|
| `--summary` | `-s` | New summary |
| `--description` | `-d` | New description (plain text or ADF) |
| `--description-file` | | Read description from file |
| `--assignee` | `-a` | New assignee (email, `@me`, `default`) |
| `--labels` | `-l` | Set labels |
| `--remove-labels` | | Remove specific labels |
| `--remove-assignee` | | Clear assignee |
| `--type` | `-t` | Change issue type |
| `--from-json` | | JSON file with updates |
| `--generate-json` | | Print JSON template |

**Control:**

| Flag | Short | Description |
|---|---|---|
| `--yes` | `-y` | Skip confirmation |
| `--ignore-errors` | | Continue past failures |
| `--json` | | JSON output |

## workitem transition

Change issue status.

```
acli jira workitem transition [flags]
```

**Targeting (pick one):**

| Flag | Short | Description |
|---|---|---|
| `--key` | `-k` | Comma-separated issue keys |
| `--jql` | | JQL query |
| `--filter` | | Saved filter ID |

**Required:**

| Flag | Short | Description |
|---|---|---|
| `--status` | `-s` | Target status name |

**Control:**

| Flag | Short | Description |
|---|---|---|
| `--yes` | `-y` | Skip confirmation |
| `--ignore-errors` | | Continue past failures |
| `--json` | | JSON output |

## workitem assign

Assign issues.

```
acli jira workitem assign [flags]
```

**Targeting (pick one):**

| Flag | Short | Description |
|---|---|---|
| `--key` | `-k` | Comma-separated issue keys |
| `--jql` | | JQL query |
| `--filter` | | Saved filter ID |
| `--from-file` | `-f` | Read issue keys from file |

**Assignment:**

| Flag | Short | Description |
|---|---|---|
| `--assignee` | `-a` | Email, account ID, `@me`, or `default` |
| `--remove-assignee` | | Clear assignee |

**Control:**

| Flag | Short | Description |
|---|---|---|
| `--yes` | `-y` | Skip confirmation |
| `--ignore-errors` | | Continue past failures |
| `--json` | | JSON output |

## workitem clone

Clone issues.

```
acli jira workitem clone [flags]
```

**Targeting (pick one):**

| Flag | Short | Description |
|---|---|---|
| `--key` | `-k` | Comma-separated issue keys |
| `--jql` | | JQL query |
| `--filter` | | Saved filter ID |
| `--from-file` | `-f` | Read issue keys from file |

**Options:**

| Flag | Description |
|---|---|
| `--to-project` | Target project key |
| `--to-site` | Target Atlassian site (cross-site cloning) |
| `--yes` | Skip confirmation |
| `--ignore-errors` | Continue past failures |
| `--json` | JSON output |

## workitem comment create

Add a comment.

```
acli jira workitem comment create [flags]
```

**Targeting (pick one):**

| Flag | Short | Description |
|---|---|---|
| `--key` | `-k` | Comma-separated issue keys |
| `--jql` | | JQL query |
| `--filter` | | Saved filter ID |

**Content (pick one):**

| Flag | Short | Description |
|---|---|---|
| `--body` | `-b` | Comment text (plain text or ADF JSON) |
| `--body-file` | `-F` | Read from file (plain text or ADF JSON) |
| `--editor` | | Open text editor |

**Options:**

| Flag | Description |
|---|---|
| `--edit-last` | Update the last comment by same author instead of creating new |
| `--ignore-errors` | Continue past failures |
| `--json` | JSON output |

## workitem comment list

List comments on an issue.

```
acli jira workitem comment list [flags]
```

| Flag | Description |
|---|---|
| `--key` | Issue key (required) |
| `--json` | JSON output |
| `--limit` | Max comments per page (default 50) |
| `--order` | Sort: `+created` (default), `updated` |
| `--paginate` | Fetch all pages |

## workitem link create

Create a link between issues.

```
acli jira workitem link create [flags]
```

| Flag | Description |
|---|---|
| `--out` | Outward issue key (e.g., the one that "blocks") |
| `--in` | Inward issue key (e.g., the one that "is blocked by") |
| `--type` | Link type name (use `link type` to list available types) |
| `--from-json` | JSON file for bulk link creation |
| `--from-csv` | CSV file (columns: outward key, inward key, link type) |
| `--generate-json` | Print JSON template |
| `--ignore-errors` | Continue past failures |
| `--yes` | Skip confirmation |

## workitem link list

List links on an issue.

```
acli jira workitem link list --key KEY-123 [flags]
```

| Flag | Description |
|---|---|
| `--key` | Issue key (required) |
| `--json` | JSON output |

## workitem link type

List available link types.

```
acli jira workitem link type [flags]
```

| Flag | Description |
|---|---|
| `--json` | JSON output |

## project list

List visible projects.

```
acli jira project list [flags]
```

## project view

View project details.

```
acli jira project view [flags]
```

| Flag | Description |
|---|---|
| `--key` | Project key |
| `--json` | JSON output |

## auth status

Show current authentication status.

```
acli jira auth status
```

## auth login

Authenticate.

```
acli jira auth login [flags]
```

| Flag | Short | Description |
|---|---|---|
| `--site` | `-s` | Atlassian site domain (required) |
| `--email` | `-e` | User email (required for token auth) |
| `--token` | | Read API token from stdin |
| `--web` | `-w` | Browser-based OAuth |

## auth logout / auth switch

```
acli jira auth logout
acli jira auth switch
```
