---
name: typescript-best-practices
description: Typescript best practices
---

## Functions

- Avoid functions with more than 2 positional arguments. Use object arguments instead
```ts
// Bad
function compileMessage(message: Message, fallbackId: string, immediate: bool, parts: Parts)
// good
function compileMessage(message, {fallbackId, immediate, parts}: {fallbackId: string; immediate:bool, parts: parts})
```


## Types

- As much as possible types should be infered and not dupliated across files. Use or create typing utilities to extract and transform related types instead of creating duplicates.
