---
name: test
description: >
  Verify a bug fix with comprehensive testing using Quay's test infrastructure.
  Creates regression tests, runs the full suite, and documents results.
allowed-tools:
  - Bash(bash .claude/scripts/format-and-lint.sh *)
  - Bash(git *)
  - Bash(make *)
  - Bash(pytest *)
  - Bash(python *)
  - Bash(pre-commit *)
  - Bash(npm *)
  - Bash(npx *)
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Agent
  - AskUserQuestion
---

# Test & Verify Fix

Verify the bug fix works correctly and create comprehensive tests to prevent
regression.

## Process

### Step 1: Survey Existing Test Patterns

Before writing any tests, examine how the project already tests its code:

```bash
# Check for test configuration
cat pytest.ini setup.cfg pyproject.toml 2>/dev/null | head -30
# Find existing tests near the modified code
find . -name '*test*' -path '*/tests/*' | head -20
```

Read 2-3 existing test files in the same area. Look for:

- Test structure (arrange/act/assert, fixtures, factories)
- Assertion style (`assert`, `pytest.raises`)
- Mocking approach (`unittest.mock`, `pytest` fixtures)
- Shared test helpers in `conftest.py`

### Step 2: Create Regression Test

- Write a test that reproduces the original bug
- Verify the test **fails** without the fix (proves it catches the bug)
- Verify the test **passes** with the fix (proves the fix works)
- Use descriptive test names that reference the ticket
- Match the style of existing tests

### Step 3: Unit Testing

- Test the specific functions/methods that were modified
- Cover all code paths in the fix
- Test edge cases identified during diagnosis
- **Test all states/phases/conditions**: If the fix involves state-dependent
  logic, ensure tests cover ALL possible states, not just common ones
- **Test feature interactions**: If the fix involves multiple interacting
  features, test their combinations

### Step 4: Integration Testing

- Test the fix in realistic scenarios with dependent components
- Verify end-to-end behavior matches expectations
- Test interactions with databases, APIs, or external systems

### Step 5: Run the Full Test Suite (MANDATORY)

This step is not optional. Do not run only your new tests.

**Backend:**

```bash
make unit-test           # Unit tests
make registry-test       # Integration tests
make types-test          # mypy type checking
```

**Frontend (if UI changes):**

```bash
cd web && npx cypress run  # E2E tests
cd web && npm test          # Unit tests
```

If the project has separate test directories, run ALL of them. If tests fail:

- Investigate whether the test was wrong or the fix broke something
- Fix and re-run until the full suite passes
- **Do not proceed until the full suite passes**

### Step 6: Lint and Format All Modified Files

```bash
bash .claude/scripts/format-and-lint.sh
```

Run on both source files and test files. Test code must meet the same
formatting standards as production code.

### Step 7: Manual Verification

- Execute the original reproduction steps from the reproduction report
- Verify the expected behavior is now observed
- Test related functionality to ensure no side effects

### Step 8: Document Test Results

Save to `artifacts/quay-bugfix/tests/verification.md`:

```markdown
# Test Verification: <TICKET>

## Test Summary
<Overview of testing performed>

## Regression Test
- **Location:** `<test file path>`
- **Test name:** `<test function name>`
- **Fails without fix:** Yes / No
- **Passes with fix:** Yes / No

## Test Results
| Suite | Command | Result | Details |
|-------|---------|--------|---------|
| Unit | `make unit-test` | Pass/Fail | <details> |
| Integration | `make registry-test` | Pass/Fail | <details> |
| Types | `make types-test` | Pass/Fail | <details> |
| Lint | `format-and-lint.sh` | Pass/Fail | <details> |

## Manual Testing
<Steps performed and observations>

## Coverage
- Edge cases covered: <list>
- States tested: <list all states tested>
- Known limitations: <any gaps>
```

## Confidence Assessment

Include this section at the end of your verification artifact:

```markdown
## Confidence Assessment
- **Level**: high | medium | low
- **Score**: <0-100 integer>
- **Score rationale**: <1-2 sentences>
- **Open questions**: <bullet list, or "None">
```

Confidence signals for this phase:
- **High**: All tests pass, regression test directly covers the fix, full suite green
- **Medium**: Most tests pass but some edge cases untested or partial suite run
- **Low**: Test failures, unable to write targeted regression test, or partial suite run

## Output

- New test files in the project repository
- `artifacts/quay-bugfix/tests/verification.md`

## When This Phase Is Done

Report: tests added, full suite status, where the report was written.
