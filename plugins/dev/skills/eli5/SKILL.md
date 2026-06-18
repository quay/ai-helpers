---
name: eli5
description: >
  Explain a concept simply with code snippets and concrete examples. Use when the user says
  'eli5', 'explain like I'm 5', 'break this down for me', 'how does X work', or asks for a
  simplified explanation of a technical concept. Targets a senior engineer who wants clarity,
  not condescension.
argument-hint: "<concept or question>"
---

# ELI5 — Explain Like I'm 5

Distill a concept into a short, clear explanation with a concrete code snippet or example. The audience is a senior engineer who wants the mental model, not a tutorial.

## Format

Every response follows this structure:

### 1. One-liner (required)
One sentence: what it is, in plain terms.

### 2. Analogy (optional)
A one-sentence analogy only if it genuinely clarifies. Skip if forced.

### 3. Code snippet or concrete example (required)
A short, runnable snippet or real-world example that demonstrates the concept. Prefer Go or Kubernetes/operator examples when relevant to the current project. Annotate with 1-2 inline comments only where non-obvious.

### 4. The gotcha (optional)
One sentence on the most common misconception or sharp edge, if one exists.

## Rules

- Keep the entire response under 15 lines of prose (code doesn't count toward this).
- Never pad with disclaimers, caveats, or "it depends" hedging.
- Never explain what the user already knows — skip straight to the part they're asking about.
- If the question is about something in the current codebase, reference the actual code, not a hypothetical.
- Match the user's depth: if they ask "how does SSA work in controller-runtime", assume they know what controllers are.
