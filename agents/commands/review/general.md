## Errors

- **Keep one source of truth.** Duplicate state attracts scrutiny: “playingState and also isPlaying” is exactly the kind of divergence you flag.
- **No magic strings** I like to have my magic strings in constants in a constants file. If there are multiple of the same type they should be grouped together in some way depending on the language of choice by using an object, struct, plain constant naming etc.
- **Inline functions used in only one place.** A function with a single caller should be inlined into that caller.
- **Parse, don't validate.** Turn untrusted input into a typed value once, at the boundary, and pass that type inward. Report checks that validate data and throw the result away (functions that check and return `void`), and re-validation of data that was already parsed.
- **Make illegal states unrepresentable.** Model data so invalid combinations can't be built: a union of variants instead of optional fields or booleans that must agree with each other.
- **Keep refactors and behaviour changes in separate PRs.** A PR that changes behaviour should not also rename, move or reformat code.
- **Bug fixes come with a regression test.** The test reproduces the bug and fails without the fix.

### Error handling

- All errors, or as much as possible, should be typed and handled. One should never swallow errors. Report them to metrics and/or to the user if they are relevant to him
- **Handle each error once.** Either handle it (log, report, recover) or return/throw it, never both. Logging and then rethrowing reports the same failure twice.
- **Never branch on error message strings.** Use a typed discriminant (error class, `code`, union tag) instead of matching `error.message`.

## Flags

- **Imperative simple code** unless the language is declarative we should always write declarative code that is simple and easy to read with minimal abstractions and high code colocation.
- **Extra code needs a concrete use case.** You question speculative features, redundant validation, and caches with little practical benefit.
- **booleans are almost always a bad idea** if a value could take more than 2 values possible in the future its better to use a union of strings
- **Prefer duplication over the wrong abstraction.** Ask whether a shared helper that gains a parameter or flag to serve one more caller should be inlined back into its callers.
- **Push ifs up and fors down.** Ask whether a condition inside a function belongs in its caller, and whether a function called in a loop should take the whole batch instead.
- **Name complex conditions.** Suggest splitting a long boolean expression into well-named variables.
- **Log one wide structured event per request.** Suggest one structured event per request or job, carrying a request ID and the context gathered along the way, instead of scattered string logs.
