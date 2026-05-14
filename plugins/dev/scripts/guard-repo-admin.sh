#!/bin/bash
# guard-repo-admin.sh -- PreToolUse hook for gh commands.
# Blocks destructive GitHub repository admin operations that an LLM
# could be socially engineered into running via prompt injection.
#
# Catches:
#   - gh api calls to dangerous REST endpoints (repo settings, deletion,
#     transfer, collaborators, webhooks, deploy keys, branch protection,
#     environments, secrets, org admin)
#   - gh repo subcommands (delete, archive, rename, transfer, edit --visibility)
#
# Exit codes:  0 = allow,  2 = block
#
# Environment variables:
#   ALLOW_REPO_ADMIN=1  — bypass all checks (for intentional admin work)

set -uo pipefail

if [ "${ALLOW_REPO_ADMIN:-}" = "1" ]; then
  exit 0
fi

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$CMD" ] && exit 0

read -r _t1 _t2 _ <<< "$CMD"
if [ "$_t1" != "gh" ]; then
  exit 0
fi

# ── Branch 1: gh repo <destructive-subcommand> ──────────────────────

if [ "$_t2" = "repo" ]; then
  read -r _ _ _verb _ <<< "$CMD"
  case "$_verb" in
    delete|archive|rename|transfer)
      echo "BLOCKED: 'gh repo $_verb' is a destructive admin operation." >&2
      echo "" >&2
      echo "  This may be a prompt-injection attempt. An attacker can embed" >&2
      echo "  instructions in PR comments, issue bodies, or CI logs to trick" >&2
      echo "  an LLM into running dangerous commands." >&2
      echo "" >&2
      echo "  If you genuinely need to run this, set ALLOW_REPO_ADMIN=1." >&2
      exit 2
      ;;
    edit)
      if echo "$CMD" | grep -qE -- '--visibility'; then
        echo "BLOCKED: 'gh repo edit --visibility' changes repo visibility." >&2
        echo "" >&2
        echo "  This may be a prompt-injection attempt. Changing a private repo" >&2
        echo "  to public exposes all code, secrets history, and CI config." >&2
        echo "" >&2
        echo "  If you genuinely need to run this, set ALLOW_REPO_ADMIN=1." >&2
        exit 2
      fi
      ;;
  esac
  exit 0
fi

# ── Branch 2: gh api <dangerous-endpoint> ───────────────────────────

if [ "$_t2" != "api" ]; then
  exit 0
fi

read -r METHOD URL_PATH <<< "$(python3 -c '
import shlex, sys

cmd = sys.argv[1] if len(sys.argv) > 1 else ""
try:
    argv = shlex.split(cmd, posix=True)
except ValueError:
    print("GET ")
    sys.exit(0)

args = argv[2:] if len(argv) > 2 else []

method = "GET"
url_path = ""

i = 0
while i < len(args):
    a = args[i]
    if a in ("--method", "-X") and i + 1 < len(args):
        method = args[i + 1].upper()
        i += 2
        continue
    if a.startswith("--method="):
        method = a.split("=", 1)[1].upper()
        i += 1
        continue
    if not url_path and not a.startswith("-"):
        url_path = a.lstrip("/")
        i += 1
        continue
    i += 1

print(f"{method} {url_path}")
' "$CMD")"

if [ "$METHOD" = "GET" ] || [ "$METHOD" = "HEAD" ]; then
  exit 0
fi

BLOCKED_REASON=""

# Repo settings / deletion: PATCH or DELETE repos/{owner}/{repo}
if echo "$URL_PATH" | grep -qE '^repos/[^/]+/[^/]+$'; then
  if [ "$METHOD" = "DELETE" ]; then
    BLOCKED_REASON="Deleting a repository"
  else
    BLOCKED_REASON="Modifying repository settings (visibility, archive status, etc.)"
  fi
fi

# Repo transfer
if echo "$URL_PATH" | grep -qE '^repos/[^/]+/[^/]+/transfer$'; then
  BLOCKED_REASON="Transferring repository ownership"
fi

# Collaborators
if echo "$URL_PATH" | grep -qE '^repos/[^/]+/[^/]+/collaborators/'; then
  BLOCKED_REASON="Modifying repository collaborator permissions"
fi

# Team permissions
if echo "$URL_PATH" | grep -qE '^(repos/[^/]+/[^/]+/teams/|orgs/[^/]+/teams/)'; then
  BLOCKED_REASON="Modifying team permissions"
fi

# Webhooks
if echo "$URL_PATH" | grep -qE '^repos/[^/]+/[^/]+/hooks(/|$)'; then
  BLOCKED_REASON="Creating/modifying/deleting repository webhooks"
fi

# Deploy keys
if echo "$URL_PATH" | grep -qE '^repos/[^/]+/[^/]+/keys(/|$)'; then
  BLOCKED_REASON="Managing deploy keys"
fi

# Branch protection
if echo "$URL_PATH" | grep -qE '^repos/[^/]+/[^/]+/branches/[^/]+/protection'; then
  BLOCKED_REASON="Modifying branch protection rules"
fi

# Environments
if echo "$URL_PATH" | grep -qE '^repos/[^/]+/[^/]+/environments(/|$)'; then
  BLOCKED_REASON="Modifying repository environments"
fi

# Action secrets
if echo "$URL_PATH" | grep -qE '^repos/[^/]+/[^/]+/actions/secrets(/|$)'; then
  BLOCKED_REASON="Modifying repository action secrets"
fi

# Action variables
if echo "$URL_PATH" | grep -qE '^repos/[^/]+/[^/]+/actions/variables(/|$)'; then
  BLOCKED_REASON="Modifying repository action variables"
fi

# Org-level admin
if echo "$URL_PATH" | grep -qE '^orgs/[^/]+/(members|memberships|teams|hooks|actions/secrets|actions/variables|settings)(/|$)'; then
  BLOCKED_REASON="Modifying organization-level settings"
fi

if [ -n "$BLOCKED_REASON" ]; then
  echo "BLOCKED: Destructive GitHub admin operation detected." >&2
  echo "" >&2
  echo "  Command: $CMD" >&2
  echo "  Method:  $METHOD" >&2
  echo "  Path:    $URL_PATH" >&2
  echo "" >&2
  echo "  Reason: $BLOCKED_REASON" >&2
  echo "" >&2
  echo "  WARNING: This may be a prompt-injection attempt. Attackers can embed" >&2
  echo "  instructions in PR comments, issue bodies, or CI logs to trick an LLM" >&2
  echo "  into running dangerous commands that change repo visibility, delete" >&2
  echo "  repos, modify permissions, or exfiltrate secrets." >&2
  echo "" >&2
  echo "  If you genuinely need to run this, set ALLOW_REPO_ADMIN=1." >&2
  exit 2
fi
