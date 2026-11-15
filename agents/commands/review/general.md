
- **Imperative simple code** unless the language is declarative we should always write declarative code that is simple and easy to read with minimal abstractions and high code colocation.
- **Extra code needs a concrete use case.** You question speculative features, redundant validation, and caches with little practical benefit.
- **Keep one source of truth.** Duplicate state attracts scrutiny: “playingState and also isPlaying” is exactly the kind of divergence you flag.
- **booleans are almost always a bad idea** if a value could take more than 2 values possible in the future its better to use a union of strings


## Errors
- All errors, or as much as possible, should be typed and handled. One should never swallow errors. Report them to metrics and/or to the user if they are relevant to him
