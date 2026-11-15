# Interfaces

A graph of the contracts this PR adds or changes: the seams other code, services or stored data depend on. Code behind a good contract can be refactored later without touching anything else, so this tab is where the reviewer checks what is expensive to get wrong. Internals stay out.

```json
{
  "summary": "markdown, optional",
  "nodes": [
    {
      "id": "delivery-event",
      "label": "webhook.delivery.requested",
      "kind": "event",
      "tier": "stored-or-wire | cross-feature",
      "group": "src/webhooks/",
      "changed": "added | modified | removed | unchanged",
      "description": "markdown",
      "signature": "type DeliveryRequested = { endpointId: string; payload: unknown; attempt: number }",
      "previousSignature": "type DeliveryRequested = { endpointId: string; payload: unknown }",
      "pseudocode": ["optional", "lines"],
      "refs": [{ "hunk": "h3", "lines": [12, 40] }]
    }
  ],
  "edges": [{ "from": "api-route", "to": "delivery-event", "label": "emits" }]
}
```

## What is a contract

An interface is a contract when changing its shape would force changes in code, services or data outside the part of the codebase that owns it. Judge by that blast radius, not by whether it is exported: languages like TypeScript have no real modules, so "owner" means the feature folder, package or service the code belongs to.

`tier` says how hard the contract is to change:

- `stored-or-wire`: shapes that outlive one deploy or cross a process. Database and CMS schemas, migrations and generated types; HTTP routes with their request and response shapes; events, queue and job payloads; URLs, env and config keys; a package's public API. Changing one needs data migration, coordinated deploys or care for old clients.
- `cross-feature`: in-process interfaces used by unrelated code. A component, hook, function or type that a different feature imports, renders or calls, such as one feature borrowing another's hook. Changing one means editing its callers, but within one PR.

Not contracts, and left out: helpers, sub-components, private types and the steps of one job or flow that only their own feature uses, even when exported for tests. They are reviewed in the Review tab.

Leave the tab out when the PR adds or changes no contract.

## Fields

- Nodes are contracts. Include every contract the PR adds, changes or removes. Add an `unchanged` contract only when the PR starts depending on it (a new caller of another feature's hook) or when it explains a changed one; the page fades unchanged nodes.
- `group` is the owner: the feature folder, package or service that defines the contract, such as `src/webhooks/` or `packages/billing`. External systems the PR talks to (a third-party API, a queue) can be their own group. Edges between groups are the seams.
- `signature` is the contract as declared at the head commit (before the PR for removed ones), in the file's language: the type, props, function head, a table's `CREATE TABLE`, a route's request and response types, an event's payload. Trim it to the contract itself: cards show up to 12 lines of up to 72 characters, and the details section shows all of it.
- `previousSignature`: for a `modified` contract, the same declaration at the base commit. The page shows the two as a line diff, so keep both trimmed the same way. Leave it out for added, removed and unchanged ones.
- `description`: what the contract is for, what changed in it, and what its callers or consumers must now do differently. For `stored-or-wire` contracts also say what happens to existing data, old clients or in-flight messages.
- `pseudocode`: optional, a few lines on the behaviour behind the contract that callers rely on, such as error cases and side effects.
- Edges go from the user of a contract to the contract, labelled with the relationship: "calls", "renders", "emits", "consumes", "reads", "writes", "implements".
- `summary`: one or two sentences on which seams the PR touches, naming the `stored-or-wire` ones first.

## Referenced types

A reviewer should understand a contract without looking up its custom types. Keep signatures accurately typed, including inferred return properties; do not abbreviate them to untyped lists such as `state; error; result`.

Put referenced definitions in the graph's top-level `types` array, once per source identity. Each node lists the definitions its signature uses in `types`, ordered by relevance. Definitions explain types without adding more contract nodes to the graph.

```json
{
  "types": [
    {
      "id": "delivery-mode",
      "name": "DeliveryMode",
      "source": { "path": "src/webhooks/types.ts", "line": 3 },
      "type": "\"immediate\" | \"queued\""
    },
    {
      "id": "delivery-options",
      "name": "DeliveryOptions",
      "source": { "path": "src/webhooks/types.ts", "line": 8 },
      "fields": [
        { "name": "endpointId", "type": "string" },
        { "name": "mode", "type": "DeliveryMode", "ref": "delivery-mode" }
      ]
    }
  ]
}
```

The corresponding contract node uses `"types": [{ "id": "delivery-options", "expanded": [] }, { "id": "delivery-mode" }]`. An object field can refer to another definition through `ref`; it retains the declared type, including wrappers such as `[]`, `Promise<...>` and nullable unions.

- Give each definition either `type` (a resolved alias, union or function type) or `fields` (every top-level object property). Preserve literal values, optional properties, nullability and union branches. Keep discriminated unions as unions rather than merging them into an object with optional fields.
- A short one-line alias (a union of literals, say) shows its value beside its name in the signature, so the card reads `type: FlowRunResultType = "image" | "video" | "audio"`. Set `"inline": false` on an alias too long or noisy for that. Object type names are selectable and open their definitions in the inspector. Native/framework types such as `File`, `AbortSignal` and `React.JSX.Element` may stay named.
- **Relevant branches first:** all top-level fields remain visible; nested objects start collapsed except branches needed to understand the PR. A branch can be relevant without changing. For example, `"expanded": ["outputs", "request.headers"]` opens those branches and their ancestors. Pick relevance for each contract, not globally on the shared definition. The reviewer can expand all branches.
- Read definitions from the reviewed commits. `source` points to the exact file and declaration line; `side` defaults to `head`, or is `base` for a removed definition. Supply `previous: { "type": "..." }` or `previous: { "fields": [...] }` when an existing definition changes, so resolved values and fields show before/after. Do not guess unavailable definitions.
- Cycles stop at a named recursive reference with a source link. Large literal unions can stay a `type` string with `"inline": false`, so they show in the inspector instead of flooding the graph card.

Use the interactive definitions rather than copying the same shapes into descriptions. Descriptions should explain behavior and consumer obligations. The page shows definitions in a side inspector, closed until the reviewer selects a type name, the card's **Types** button or presses `gd`; pinned, it follows the cursor from contract to contract.
