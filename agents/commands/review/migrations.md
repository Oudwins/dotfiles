## Errors

- Don't assume at same time deploy. This generally means you have to ship migrations in steps. first make the change with backgrounds compat, then nuke the old version
- **Expand, migrate, contract.** Ship a schema change over separate deploys: add the new shape and write to both old and new; make readers accept both; backfill; remove the old shape in a later PR.
- **Add constraints wherever you can.** Use `NOT NULL`, unique and foreign-key constraints instead of relying on application code to keep data valid.
