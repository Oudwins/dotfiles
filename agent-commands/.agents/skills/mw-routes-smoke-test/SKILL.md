---
name: mw-routes-smoke-test
description: Browser-tests representative marketing website routes in English and another locale. Use when explicitly asked to smoke-test the dev server, check every page type, or verify a PR's frontend behavior.
disable-model-invocation: true
---

# Route Smoke Test

Verify the running frontend by public URL pattern, not by CMS template. Discover coverage from the current codebase so newly added collections and route families are included automatically.

This is a read-only verification task. Do not edit application code, change CMS content, submit forms, commit changes, or clear caches unless explicitly asked.

## Discover Coverage

Read the repository instructions, then build a checklist using these sources:

- `shared/collections-types.ts`: `PAGE_COLLECTION_SLUGS` identifies the current page collections.
- `shared/realSlugToDocument.ts`: identifies collection ownership of public path prefixes.
- `shared/documentToRealSlug.ts`: constructs public URLs from CMS document slugs.
- `frontend-next/src/app/(pages)/**/page.tsx`: defines actual route patterns, including listings, filtering, pagination, nested resources, and pages backed by external APIs.

Inspect shared page factories and data loaders where necessary to identify each route's data source and meaningful variants.

Route groups such as `(default)` do not appear in URLs. Dynamic segments require real sample values. Catch-all routes require representative CMS paths.

Reconcile these sources into a coverage matrix:

- Include at least one valid page per in-scope public route family.
- Include newly added collections and route families, not just those covered by previous tests.
- Treat distinct nested routes separately, such as event parent, child, and resource pages.
- Cover all content listings and their filtered or paginated route patterns.
- Include 15-20 general `pagesv2` pages: homepage, `/text-to-speech`, major product pages, and randomly selected top-level and nested paths.
- Record the exact sampled URLs and any families without usable local samples.

Reuse previous checklists only as a starting point. Exclude auth, internal utilities, previews, protected experiences, and experiments unless requested.

## Prepare

Confirm the running frontend and CMS addresses. Defaults are `http://localhost:4000` and `http://localhost:14001`.

Discover real published documents using read-only CMS access. Prefer canonical `route.slug` values and samples available in both test languages. Use the existing access guidance; never expose credentials or tokens.

Test English and another supported language, preferably French. Set the locale cookie explicitly before each language pass so previous browser state does not redirect English requests into another locale.

## Browser Verification

Use the `mw-agent-browser` workflow. Repeated checks may be automated with Playwright while retaining browser-level error and network capture.

For every sampled URL:

- Check HTTP status and final URL.
- Confirm meaningful page content renders, rather than an error fallback or blank page.
- Check uncaught exceptions, hydration errors, and console errors.
- Check failed content/data requests and broken visible images.
- Check relationship-derived links for missing parent paths, `undefined`, `null`, or malformed slugs.
- Scroll through the page to exercise lazy-loaded content.
- Confirm the expected locale, accounting for configured fallback, redirect, and noindex policies.

HTTP 200 alone is not a pass if the page crashes after hydration.

On listings, exercise available pagination, category/platform/industry filters, and Load More. Verify content changes, requests succeed, and links preserve the locale. Do not submit lead-capture forms or trigger generation workflows.

Use isolated browser sessions for parallel work, with limited concurrency to avoid overwhelming the dev server.

## Investigate Failures

Retry transient timeouts and dev-server disconnects before classifying them as persistent failures.

Distinguish:

- Application bugs.
- Unavailable local services.
- Telemetry or third-party failures.
- Expected locale policies.
- Missing local sample data.
- Headless-browser limitations.

Do not dismiss browser errors as environmental without evidence. Mark unavailable samples as coverage gaps, not passes.

Investigate failures using source code and fresh CMS responses. Compare fresh responses with cached frontend behavior where relevant, without modifying or clearing caches.

For PR verification, inspect the diff before attributing a failure to the changes. Label findings as introduced, pre-existing, environment-related, or uncertain.

## Report

Save the checklist, per-URL results, and useful failure screenshots in a temporary location.

Report:

- Distinct URLs tested and total route-locale checks.
- Coverage by general pages, detail routes, and listings.
- Persistent failures first, with reproducible URLs, causes, and source references.
- Transient failures and whether retries succeeded.
- Nonfatal console, hydration, cache, and telemetry issues.
- Interaction results and localized navigation behavior.
- Untested families and other limitations.

Do not claim everything is error-free merely because pages rendered. State that no application code or CMS content was changed, and close only browser sessions created for this test.
