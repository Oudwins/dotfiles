# Quick view

The code the reviewer has to read when they don't read the whole PR. A change that stays inside its feature can be refactored later without touching anything else. What needs a human's eyes is where it reaches outside the feature, exposes an endpoint, touches the database, sits on a security boundary or runs often. The reviewer spot-checks two things here above all: that every endpoint is secure, and that no database call will cause trouble, such as a query in a loop, a chain of dependent fetches or a query on a short interval. This tab collects that code, changed or not, so the reviewer can read and judge it.

You surface code; the reviewer judges it. Don't rate, rank or reassure: no severities, no "this is fine", no "looks safe". Captions state facts. Flags point at something you saw.

```json
{
  "summary": "markdown, optional",
  "items": [
    {
      "concern": "outside | endpoints | data | security | performance",
      "title": "POST /prompts/batch handler",
      "note": "markdown: what the code is, when it runs, what it touches",
      "flag": "markdown, optional: something you saw that the reviewer should look at",
      "code": [
        { "hunk": "h12", "lines": [40, 66] },
        { "path": "src/auth/gate.ts", "lines": [10, 32] }
      ]
    }
  ]
}
```

- The feature is the code this PR adds plus the existing code only it uses. Existing code with other callers counts as outside, even in the same folder.
- `summary`: where the feature lives (folders or files) and, in a sentence, how much reaches outside it, e.g. "Everything is under `app/llm-tracker/` except the grant in `collections/Users.ts` and a lint rule".
- `concern` groups items into sections, shown in the order above. A section with no items says "Nothing found", so cover each concern fully, but leave out code whose effect stays local and cheap, such as a lookup during render. Endpoints and database calls are never left out for being cheap.
- `title` names the code: a route, function, query, migration or component.
- `note` is facts only: what the code does, what triggers it (per request, per render, per item, cron), how often, what it reads and writes, who else uses it. Give counts where you can work them out, counting non-test code only ("9 parallel BigQuery reads per page load", "12 other callers"). Say so when something is inferred. Documented behaviour of a library or service (how a database runs a query) counts as fact; link or name the source.
- `flag` is optional and short: an observation, not a verdict. "`projectId` comes from the query string and is not checked against the prompt's project" rather than "insecure". A flag can come from reading code across files; say so when it is inferred. When the consequence isn't obvious, state it as a chain of facts: "Grantees can enable projects; the hourly scheduler runs paid engine calls for enabled projects".
- `code` is what the reviewer reads, in the tab. Use diff references (see Code references in SKILL.md; line numbers are each line's `n`, or `o` for removed lines, in `pr.json`) for changed code, as long as the code that matters. Use `{ "path", "lines": [start, end] }`, with a repo-relative path, for code the PR doesn't change, at the head commit (`"side": "base"` for code as it was before the PR), kept to the lines that matter, about 30 per excerpt. Use several entries when the lines that matter are far apart, e.g. a query, the loop around it and the interval that starts the loop. An item can be all unchanged code, e.g. the other readers of a table the PR changes. The page marks unchanged code itself, so titles needn't.
- Leave out test files and client-side cache plumbing (query keys, invalidation).
- Order endpoints, data, security and performance items along the flow: entry point first, storage last. Order an item's `code` the same way: what triggers it first, the database call last. Order outside items by how much else depends on them, most first. Put an item under the concern the reviewer would judge it by; when it matters to another concern too, add a short item there that says so rather than repeating it.

## Concerns

- **outside**: each place the PR crosses out of the feature:
  - shared code it changes, with its other callers (`git grep` at the head) and an excerpt of one if the change affects them
  - code from other features or packages it starts depending on (not libraries or framework code)
  - code of its own that other features now use
  - config, env, dependencies, global styles, feature flags, permissions and roles

  Exports and imports between the feature's own files are not outside; leave them out. So is wiring: changes elsewhere that only hook the new code up the usual way, such as registering a route, view or job, adding it to a menu, index or list, or a lint or build allowlist entry. Keep a wiring change only when it also changes who can access something, what gets stored, or how existing code behaves, and then put it under that concern, showing only the lines that decide it: the check, not the constants, generated types and docs that register it.
- **endpoints**: one item per entry point the PR adds or changes (route, API handler, server action, RPC or tRPC procedure, GraphQL resolver, webhook, cron, queue consumer), and per existing one that more users can now reach. `title` is the method and path, or the action's name. `code` shows, in order: where it is registered, the lines that check authentication, the lines that check permission on the specific resource (not just "logged in"), the lines that parse and validate input, and what it returns. When any of these is missing, say so in `note` and show the handler. `note` says who can call it (anonymous, any user, a role, a signed webhook) and which inputs come from the caller. Flag inputs that choose a resource (ids, slugs, paths) and are not checked against the caller, fields returned that the client didn't get before, and missing rate limits on endpoints that do paid or heavy work.
- **data**: every database query, write, migration and transaction the PR adds or changes, plus caches and file or object storage. One item per call site, or per function when its calls belong together. `code` shows the call and the code around it that decides how often it runs, back to what triggers it, even when that code sits in other files or is unchanged:
  - the enclosing loop, `map`, `forEach` or `Promise.all`, and where its list comes from
  - dependent fetches, where one await's result feeds the next query, including across functions or components (a parent fetch, then a fetch per child)
  - the trigger: the route or action, a render or effect and its dependencies, `setInterval` or `setTimeout`, a polling or `refetchInterval` option, a cron schedule, a queue or event subscription, a retry
  `note` names the table, collection or key, whether it reads or writes, and the call pattern as counts: queries per trigger, sequential or parallel, how often the trigger fires ("1 + N sequential reads per request, N = rows in `projects` for the org", "1 read every 5 s per open tab"), and whether the read is bounded (limit, pagination, a filter on an indexed column if the schema shows one). Say so when a count is inferred. Flag queries inside loops, chains of dependent awaits, short intervals, unbounded reads, writes without a transaction where several must agree, and reads with no filter on the caller's tenant or user. Add excerpts of unchanged code that reads or writes the same data (jobs, other features, schedulers), since that is where a change in shape or meaning shows up.
- **security**: what isn't an endpoint check: outbound requests, SQL or HTML built from strings, secrets, and data returned to the client that it didn't get before through something other than an endpoint (props, page data, logs).
- **performance**: code that runs per request, per render or per item and isn't a database call: awaits on other services inside loops, fan-outs, unbounded lists, client-side fetching, large additions to the client bundle. Database call patterns go under data.
