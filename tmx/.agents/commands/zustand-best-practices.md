---
description: Summarize best practices for working with Zustand
agent: build
---

# Zustand Best Practices

Summarize and apply the guidance from these articles:

- `https://tkdodo.eu/blog/working-with-zustand`
- `https://tkdodo.eu/blog/zustand-and-react-context`

Produce a concise, practical guide for working with Zustand.

## Focus Areas

Cover these recommendations clearly:

1. Only export custom hooks from Zustand modules instead of exporting the raw store hook.
2. Always use selectors, and prefer atomic selectors over selectors that return fresh objects or arrays.
3. Group actions separately from state when helpful, and explain why subscribing to a stable actions object is okay.
4. Model actions as domain events instead of generic setters so business logic stays in the store.
5. Keep store scope small. Prefer multiple focused stores over one large app-wide store.
6. Explain when a store should be truly global versus scoped to a route, feature, or reusable component subtree.
7. Describe why React Context is useful for dependency injection of a Zustand store instance, not for subscribing to changing state values.
8. Show when to use `createStore` plus a Provider instead of a global `create(...)` store:
   - initialization from props
   - isolated tests
   - reusable component instances with separate state

## Output Requirements

Return the answer in this structure:

### Summary
- 5-10 bullets with the main best practices.

### Recommended Patterns
- Short code examples for:
  - a small store module with exported selector hooks
  - separated actions
  - a scoped Zustand store using `createStore`, React Context, and a custom selector hook

### Pitfalls To Avoid
- Call out common mistakes such as:
  - subscribing to the whole store
  - returning new objects from selectors without shallow comparison
  - syncing props into a global store with `useEffect` when a scoped store is the better fit
  - using Context itself as the state container for frequently changing values

### Decision Guide
- Include a short “Use global store when...” vs “Use scoped store + Context when...” section.

Keep the tone practical and opinionated. Optimize for a teammate who wants actionable Zustand guidance, not a broad state-management overview.
