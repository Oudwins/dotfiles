# Interfaces

A graph of the interfaces this PR adds or changes, grouped by the file that defines them, and how they use each other.

```json
{
  "summary": "markdown, optional",
  "nodes": [
    {
      "id": "deliver",
      "label": "deliverWebhook",
      "kind": "function",
      "group": "src/webhooks/deliver.ts",
      "changed": "added | modified | removed | unchanged",
      "description": "markdown",
      "signature": "export async function deliverWebhook(delivery: Delivery): Promise<Result>",
      "pseudocode": ["load endpoint for delivery", "POST payload with signature header", "record attempt"],
      "refs": [{ "hunk": "h3", "lines": [12, 40] }]
    }
  ],
  "edges": [{ "from": "worker", "to": "deliver", "label": "calls" }]
}
```

- Nodes are exported functions, types, classes, endpoints, events, component props, hooks and store APIs. Include the changed ones, plus the unchanged ones they call or that call them when that explains the change.
- `group` is always the file that defines the interface, so the graph shows where each one lives.
- `signature` is the declaration as written at the head commit (before the PR for removed ones), in the file's language: the type, interface, props or function head, a table's `CREATE TABLE`, a route's request and response types. It is drawn on the graph card so the reviewer sees the shape at a glance, so trim it to the part that matters: cards show up to 12 lines of up to 72 characters, and the details section shows all of it.
- `pseudocode` is a few lines on what it does, for the reviewer to read before opening `refs`.
- Edges are labelled with the relationship: "calls", "implements", "emits", "renders", "returns".
- `description`: what the interface is for, what changed in its contract, and anything callers must now do differently.
- Backend: request and response shapes, event payloads, service functions and their error behaviour.
- Frontend: component props, hook return values, context and store APIs.
