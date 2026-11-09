# Architecture

A graph of the parts this PR touches and how they connect, so the reviewer sees where the change sits before reading code.

```json
{
  "summary": "markdown, optional",
  "nodes": [
    {
      "id": "webhook-worker",
      "label": "Webhook worker",
      "kind": "queue consumer",
      "group": "api",
      "changed": "added | modified | removed | unchanged",
      "description": "markdown",
      "pseudocode": ["optional", "lines"],
      "refs": [{ "hunk": "h3" }]
    }
  ],
  "edges": [{ "from": "api-route", "to": "webhook-worker", "label": "enqueues delivery" }]
}
```

- Nodes are modules, services, jobs, queues, databases, external APIs, pages, components or stores, whatever level makes the change clear. Aim for 4-15.
- Include the unchanged neighbours that give the change its context, marked `unchanged`.
- Edges show calls or data flow, labelled with what flows or why ("enqueues delivery", "reads session").
- `group` boxes related nodes: an app, package, layer or process boundary. Leave it out when there is nothing to group.
- `description` says the node's role and what this PR changes about it. `refs` points at the code that implements the change.
- `summary`: one or two sentences on the shape of the change, e.g. "Delivery moves from the request path to a queue".
- Backend: follow the request or job from its entry point (route, handler, cron, consumer) through services to storage, queues and external calls.
- Frontend: follow the route or page down the component tree to the hooks, stores and API calls that feed it.
