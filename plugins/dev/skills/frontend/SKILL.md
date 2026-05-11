---
name: frontend
description: >
  Load Quay React frontend context. Covers data flow, testing, and where
  Quay conventions override PatternFly defaults. Auto-invoked by /code
  when the ticket touches web/.
allowed-tools:
  - Read
  - Glob
  - Grep
---

# Quay React Frontend Context

Load this context when working on the Quay React frontend (`web/`).

## Step 1: Read project conventions

Read `web/AGENTS.md` in the target repo — it has the canonical directory
structure, commands, and stack versions. Do not duplicate that content here;
this skill covers what `web/AGENTS.md` does **not**.

## Step 2: Load PatternFly component knowledge

The `patternfly/ai-helpers` react plugin is installed as a Lola dependency.
Its agents provide generic PatternFly 6 component knowledge:

- **`pf-coding-standards`** — component structure, styling, accessibility, TypeScript
- **`pf-unit-test-standards`** — React Testing Library patterns and query priority
- **`component-structure-audit`** — required parent-child hierarchies (Toolbar > ToolbarContent, Table > Thead/Tbody, etc.)

Use that knowledge as the baseline. The overrides below take precedence
where Quay diverges from PF defaults.

## Quay Overrides

### Loading states — NEVER early-return spinners

PF coding-standards shows `if (isLoading) return <Spinner />`.
**Quay forbids this.** Use `<SuspenseLoader>` + `useSuspenseQuery`:

```tsx
// Parent
<SuspenseLoader>
  <DataComponent />
</SuspenseLoader>

// Child — data is always available, no loading check needed
function DataComponent() {
  const {data} = useSuspenseQuery({queryKey: ['repos', ns], queryFn: ...});
  if (!data.length) return <EmptyState titleText="No results" />;
  return <Table data={data} />;
}
```

### Test framework — Vitest, not Jest

PF test-standards use Jest. Quay uses Vitest:

| PF says | Quay does |
|---------|-----------|
| `jest.fn()` | `vi.fn()` |
| `jest.mock()` | `vi.mock()` |
| `jest.clearAllMocks()` | `vi.clearAllMocks()` |
| `(fn as jest.Mock)` | `vi.mocked(fn)` |
| `import from '@jest/globals'` | `import {vi} from 'vitest'` |

Always import `render` from `src/test-utils` (not `@testing-library/react`).
It wraps with QueryClient, UIProvider, and RecoilRoot.

### State management — strict layering

| State type | Tool |
|-----------|------|
| Server state | TanStack Query (`useSuspenseQuery` / `useMutation`) |
| UI state | React Context (`SidebarContext`, `AlertContext`, `AuthContext`) |
| Legacy | Recoil (`atoms/`) — **do not use in new code** |

### Axios — use the configured instance

Never import `axios` from the package directly. Use `src/libs/axios.ts` —
it has CSRF token interceptors, auth middleware, and error handling.

## Data Flow

```text
Component → Hook (src/hooks/UseX.ts) → Resource (src/resources/XResource.ts) → Axios → API
```

- **Components** call hooks, never resources or axios directly
- **Hooks** use `useSuspenseQuery` for reads, `useMutation` for writes
- **Resources** are pure async functions — no React hooks, handle pagination
- **Query keys** follow `['resource', ...params]` (e.g. `['repositories', namespace]`)

### Mutations with cache invalidation

```tsx
const mutation = useMutation({
  mutationFn: (data: UpdateData) => updateResource(data),
  onSuccess: () => {
    queryClient.invalidateQueries({queryKey: ['resource']});
  },
});
```

## Testing Patterns

### Unit tests (Vitest)

```typescript
import {describe, it, expect, vi} from 'vitest';
import {render, screen, userEvent} from 'src/test-utils';
import axios from 'src/libs/axios';

vi.mock('src/libs/axios');

describe('MyComponent', () => {
  it('submits form data', async () => {
    const user = userEvent.setup();
    render(<MyComponent />);
    await user.click(screen.getByRole('button', {name: 'Submit'}));
    expect(vi.mocked(axios.post)).toHaveBeenCalledOnce();
  });
});
```

- Co-locate tests: `Component.test.tsx` next to `Component.tsx`
- Mock at network boundary: `vi.mock('src/libs/axios')` or `axios-mock-adapter`
- Query priority: `getByRole` > `getByLabelText` > `getByText` > `getByTestId`
- Always `userEvent`, never `fireEvent`

### E2E tests (Playwright)

- Location: `web/playwright/e2e/`
- Real APIs, no mocks — requires running Quay stack
- Prefer `data-testid` selectors