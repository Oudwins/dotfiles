## Errors

- **Check each flag through one decision function.** Wrap the check in a named function in one place (`canCancelOrders()`) instead of calling `isEnabled("flag-name")` throughout the code.
- **Test both the on and off states.** Both code paths can run in production, so both need tests.
