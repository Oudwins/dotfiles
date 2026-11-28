## Errors

- No useEffect or as little as possible
- **use absense instead of hide flags**
- **Pass inputs directly to operations.** Prefer `sendMessage(text)` over requiring `setMessage(text)` followed by `sendMessage()`.
- Basically never use function style components in react inside other components for rendering. Almost always use <Component /> style instead
- **Reset state with a `key`, not an effect.** When a component's state should start over because a prop changed, render it with `key={userId}` instead of clearing state in an effect.
- **Effects that fetch need cleanup.** An effect that fetches must abort or ignore stale responses in its cleanup, otherwise a slow earlier response can overwrite a newer one.

### use state

- **It isn't state if** it comes from props, never changes, can be computed from other props or state, or its setter is only called inside an effect. Compute it during render or remove it.
- setting current time in use state is bad because it triggers rerendering
- **Make control flow direct.** prefer updating state in the event handler over effects reacting to intermediate state

## Flags

- **Don't copy props into state.** Ask whether state initialised from a prop should follow later changes to it; the copy ignores them. Fine when the prop is only an initial value (`initialX`).
- using use state to set style properties is also generally bad unless its in reaction to user input. Set the values directly
- setting use state without user input is bad. It almost always when you set use state should be because the user clicked on something
- prop drilling
