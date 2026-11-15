# Data model

The data this PR stores, passes around or reshapes, with field-level changes.

```json
{
  "summary": "markdown, optional",
  "entities": [
    {
      "name": "webhook_deliveries",
      "kind": "table",
      "changed": "added | modified | removed | unchanged",
      "description": "markdown",
      "fields": [
        { "name": "attempts", "type": "int not null default 0", "previousType": "int", "change": "modified", "note": "now incremented per retry" }
      ],
      "usage": "markdown, optional",
      "refs": [{ "hunk": "h2" }]
    }
  ]
}
```

- Entities are tables, collections, persisted documents, domain types, API payloads, events, store state or cache shapes.
- List the fields that changed. Add unchanged fields only when the reviewer needs them to understand the changed ones. `previousType` is the type before the PR, set only for modified fields; for removed fields `type` is the old type.
- `usage`: where the entity is read and written, and anything that has to stay in sync with it.
- `refs`: the schema, migration or type definition.
- Backend: include indexes, constraints, defaults and nullability, and whether existing rows need a backfill.
- Frontend: include store and cache shapes, form state and the API response types the UI relies on.
- Call out data stored in two places, or the same shape mapped between types.
