---
name: reproduce
description: >
  Systematically reproduce a Quay bug using project-specific tooling.
  Documents environment, reproduction steps, and observable behavior.
allowed-tools:
  - Bash(make *)
  - Bash(pytest *)
  - Bash(python *)
  - Bash(docker *)
  - Bash(podman *)
  - Bash(git *)
  - Bash(npm *)
  - Bash(npx *)
  - Bash(curl *)
  - Read
  - Write
  - Glob
  - Grep
  - Agent
  - AskUserQuestion
---

# Reproduce Bug

Confirm the bug exists by reproducing it systematically.

## Your Role

Methodically reproduce the bug and document its behavior so that diagnosis
and fixing can proceed with confidence.

## Process

### Step 1: Parse Bug Report

Read the assessment (`artifacts/quay-bugfix/reports/assessment.md` if it
exists) and extract:

- Bug description and expected vs actual behavior
- Affected components, versions, environment details
- Error messages, stack traces, or relevant logs
- UI vs backend classification

### Step 2: Set Up Environment

**For backend bugs:**

Check what's available and set up accordingly:

```bash
# Check for Quay's local dev setup
ls Makefile 2>/dev/null && grep -l 'local-dev' Makefile
# Check for virtual env
ls pyproject.toml requirements.txt 2>/dev/null
```

Common Quay setup approaches:

- `make local-dev-up` — full local development environment (Docker, DB, Redis)
- Virtual environment — `python -m venv .venv && pip install -r requirements.txt`
- Direct pytest — for unit-level reproduction

**For UI bugs:**

```bash
# Check for frontend dev server
ls web/package.json 2>/dev/null
```

- Start dev server if needed: `cd web && npm install && npm start`
- Default app URL: `http://localhost:9000`
- Test credentials: `user1` / `password`

### Step 3: Attempt Reproduction

Follow the steps from the assessment report. For each attempt, document:

- Exact commands or UI actions performed
- Expected behavior (from bug report)
- Actual behavior (what happened)
- Any error messages or stack traces

Try variations to understand the bug's boundaries:

- Different input values
- Different user roles/permissions
- Different database backends (PostgreSQL vs MySQL)
- Different configurations
- Race conditions (if timing-related)

### Step 4: Document Reproduction

Create a minimal set of steps that reliably reproduce the bug.

### Step 5: Write Reproduction Report

Save to `artifacts/quay-bugfix/reports/reproduction.md`:

```markdown
# Reproduction Report: <TICKET>

## Environment
- Quay version/branch: <branch>
- Setup method: <local-dev-up / venv / docker / pytest>
- Database: <PostgreSQL / MySQL / SQLite>
- Python version: <version>

## Reproduction Steps
1. <exact step>
2. <exact step>
...

## Results
- **Reproduced:** Yes / No / Intermittent
- **Success rate:** Always / Often / Sometimes / Rare
- **Expected:** <what should happen>
- **Actual:** <what does happen>
- **Error output:** <if any>

## Variations Tested
| Variation | Reproduced? | Notes |
|-----------|:-----------:|-------|
| ... | ... | ... |

## Minimal Reproduction
<Shortest path to trigger the bug>

## Notes
<Any observations, workarounds, or additional context>
```

## Confidence Assessment

Include this section at the end of your reproduction artifact:

```markdown
## Confidence Assessment
- **Level**: high | medium | low
- **Score rationale**: <1-2 sentences>
- **Open questions**: <bullet list, or "None">
```

Confidence signals for this phase:
- **High**: Bug reproduced consistently with minimal steps
- **Low**: Cannot reproduce, intermittent, or environment-dependent

## Output

- `artifacts/quay-bugfix/reports/reproduction.md`

## Error Handling

If reproduction fails:

- Document exactly what was tried and what differed from the report
- Check environment differences (versions, config, data)
- Consider the bug may be environment-specific or intermittent
- Record findings with a "Could Not Reproduce" status

## When This Phase Is Done

Report: whether the bug was reproduced, key observations, and where the
reproduction report was written.
