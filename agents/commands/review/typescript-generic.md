---
name: typescript-best-practices
description: Typescript best practices
---

## Errors

- Avoid functions with more than 2 positional arguments. Use object arguments instead
```ts
// Bad
function compileMessage(message: Message, fallbackId: string, immediate: bool, parts: Parts)
// good
function compileMessage(message, {fallbackId, immediate, parts}: {fallbackId: string; immediate:bool, parts: parts})
```

- As much as possible types should be infered and not dupliated across files. Use or create typing utilities to extract and transform related types instead of creating duplicates.
- **Derive types from the schema.** When a runtime schema exists (zod, drizzle, etc.), infer the type from it (`z.infer<typeof schema>`) instead of writing it again by hand.
- **Use discriminated unions, not a bag of optionals.** When an object represents several states, give each state its own variant with a literal tag and only that state's fields, instead of one type full of optional fields. Narrow on the tag before reading variant fields.
```ts
// Bad
type State = { status: string; data?: Data; error?: Error }
// good
type State =
  | { status: "loading" }
  | { status: "success"; data: Data }
  | { status: "error"; error: Error }
```

- **Use `as const` objects instead of `enum`.**
```ts
const Status = { Idle: "idle", Done: "done" } as const
type Status = (typeof Status)[keyof typeof Status]
```

- **Switches over a union are exhaustive.** End with a `never` check so adding a variant is a compile error.
```ts
switch (x.discriminator) {
    case "option1":
        return "option1";
    // ...other cases
    default: {
        x satisfies never;
        throw new Error(`Unhandled value: ${JSON.stringify(x)}`);
    }
}
```
