---
name: ticket
description: >
  Create, view, or update a JIRA ticket. Supports create, edit, view, assign,
  transition, check-version, set-version, and clone operations via acli CLI.
argument-hint: PROJQUAY-XXXX [action] | create [description]
allowed-tools:
  - Bash(acli jira workitem view *)
  - Bash(acli jira workitem create *)
  - Bash(acli jira workitem edit *)
  - Bash(acli jira workitem transition *)
  - Bash(acli jira workitem clone *)
  - Bash(acli jira workitem link create *)
  - Bash(curl -sS -u * https://*.atlassian.net/rest/api/3/*)
  - Read
  - Grep
  - AskUserQuestion
---

# JIRA Ticket Operations

Parse `$ARGUMENTS` to determine the action:

- Starts with `create` → **Create** a new ticket
- Contains an issue key (e.g., `PROJQUAY-1234`) → **View** by default, or the specified action
- Actions: `view`, `create`, `edit`, `assign`, `transition`, `check-version`, `set-version`, `clone`

## JIRA API Access

Use the `acli` CLI for all operations. For custom field writes (set-version, components, priority on existing issues), fall back to REST API with curl.

REST credentials: `~/.config/acli/jira_config.yaml` (email), `~/.config/acli/token.txt` or `$JIRA_API_TOKEN` (token).

Target Version field: `${JIRA_TARGET_VERSION_FIELD:-customfield_10855}`. Domain: `${JIRA_DOMAIN:-redhat.atlassian.net}`.

## Operations

### Create

Gather required fields interactively — ask the user for anything not provided in `$ARGUMENTS`:

- **Project** (required): `PROJQUAY` or `QUAYIO`
- **Type** (required): `Bug`, `Story`, `Task`, or `Epic`
- **Summary** (required): concise title, under 100 characters
- **Description** (required): expand the user's input with clarifying questions (current vs expected behavior, steps to reproduce, acceptance criteria)
- **Component**: `quay`, `quay-ui`, `quay-operator` (PROJQUAY) or `quay.io` (QUAYIO)
- **Priority**: `Critical`, `Major`, `Minor`, or `Undefined` (default)
- **Assignee**: defaults to `@me`
- **Labels**: suggest `eus-applicable` for CVE/security fixes

Present a summary for confirmation before creating.

```bash
acli jira workitem create \
  --project "$PROJECT" --type "$TYPE" --summary "$SUMMARY" \
  --description "$DESCRIPTION" --assignee "${ASSIGNEE:-@me}" \
  --label "$LABELS" --json
```

For fields acli `create` does not support natively (components, priority, epic link), set them via REST after creation:

```bash
curl -sS -u "$EMAIL:$TOKEN" -X PUT -H "Content-Type: application/json" \
  -d '{"fields":{"components":[{"name":"COMPONENT"}],"priority":{"name":"PRIORITY"}}}' \
  "https://${JIRA_DOMAIN:-redhat.atlassian.net}/rest/api/3/issue/$ISSUE_KEY"
```

For epic link, set `parent`: `{"fields":{"parent":{"key":"EPIC_KEY"}}}`.

Alternatively, use `--from-json` with `additionalAttributes` to set custom fields at creation time:

```bash
acli jira workitem create --from-json ticket.json --json
```

Where `ticket.json` includes `additionalAttributes` for custom fields like components and priority.

Report the created ticket key and URL.

### Edit

```bash
acli jira workitem edit --key "$ISSUE_KEY" --summary "$NEW_SUMMARY" --yes
```

Supported fields via acli: `--summary`, `--description`, `--assignee`, `--labels`, `--type`.

For fields requiring REST (components, priority, epic link, custom fields), use the same REST pattern as Create above.

### View (default)

```bash
acli jira workitem view "$ISSUE_KEY" --fields '*all' --json
```

Extract key, summary, status, assignee, type, priority, labels. Check `fields.customfield_10855[].name` for Target Version.

### Assign

```bash
acli jira workitem edit --key "$ISSUE_KEY" --assignee "@me" --yes
```

If a specific assignee is provided, pass their email instead of `@me`.

### Transition

```bash
acli jira workitem transition --key "$ISSUE_KEY" --status "$STATUS" --yes
```

Valid statuses: `New`, `ASSIGNED`, `POST`, `ON_QA`, `Verified`, `Release Pending`, `Closed`, `MODIFIED`

If transition fails, list available transitions with `acli jira workitem view "$KEY" --fields '*all' --json` and check the `transitions` array.

### Check Target Version

```bash
acli jira workitem view "$ISSUE_KEY" --fields '*all' --json | jq '.fields.customfield_10855'
```

If the field is a non-empty array, backporting is required after merge. If null or empty, no backporting needed.

### Set Target Version

`acli edit` does not support custom fields. Use REST with `jq` to build the payload dynamically:

```bash
jq -n --arg ver "$VERSION" --arg field "${JIRA_TARGET_VERSION_FIELD:-customfield_10855}" \
  '{fields: {($field): [{"name": $ver}]}}' | \
  curl -sS -u "$EMAIL:$TOKEN" -X PUT -H "Content-Type: application/json" -d @- \
  "https://${JIRA_DOMAIN:-redhat.atlassian.net}/rest/api/3/issue/$ISSUE_KEY"
```

### Clone

```bash
acli jira workitem clone --key "$ISSUE_KEY" --to-project "$PROJECT" --yes
```

After cloning, link the clone to the original:

```bash
acli jira workitem link create --out "$CLONE_KEY" --in "$ISSUE_KEY" --type Blocks --yes
```

If a target version is needed on the clone, set it via REST (same as Set Target Version above).

## Customer Data

Never include customer names, company names, or identifying information in ticket descriptions. Generalize customer-specific details.

## Configuration

- `JIRA_DOMAIN` — JIRA instance (default: redhat.atlassian.net)
- `JIRA_DEFAULT_EMAIL` — fallback email for auth
- `JIRA_TARGET_VERSION_FIELD` — custom field ID (default: customfield_10855)
