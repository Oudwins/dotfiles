


- No useEffect or as little as possible
- **use absense instead of hide flags**
- **Pass inputs directly to operations.** Prefer `sendMessage(text)` over requiring `setMessage(text)` followed by `sendMessage()`.


## use state
- setting current time in use state is bad because it triggers rerendering
- using use state to set style properties is also generally bad unless its in reaction to user input. Set the values directly
- setting use state without user input is bad. It almost always when you set use state should be because the user clicked on something
- **Make control flow direct.** prefer updating state in the event handler over effects reacting to intermediate state


## Props
- prop drilling
