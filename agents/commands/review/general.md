
- **Imperative simple code** unless the language is declarative we should always write declarative code that is simple and easy to read with minimal abstractions and high code colocation.
- **Extra code needs a concrete use case.** You question speculative features, redundant validation, and caches with little practical benefit.
- **Keep one source of truth.** Duplicate state attracts scrutiny: “playingState and also isPlaying” is exactly the kind of divergence you flag.
- **booleans are almost always a bad idea** if a value could take more than 2 values possible in the future its better to use a union of strings
- **No magic strings** I like to have my magic strings in constants in a constants file. If there are multiple of the same type they should be grouped together in some way depending on the language of choice by using an object, struct, plain constant naming etc.
- Careful with multiple booleans that allow for incompatible states. For example in UI code you often see isSettingsOpen, isPanelOpen... If only one can be true at a time these need to collapse into one variable that is not a boolean. Multiple booleans can be okay if they are computed values. But that is the only way they are okay


## Errors
- All errors, or as much as possible, should be typed and handled. One should never swallow errors. Report them to metrics and/or to the user if they are relevant to him
