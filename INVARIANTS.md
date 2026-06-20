# Invariants

## Authorization

- Only a terminal registered for `context.projectId` may invoke `processSplitWith`.
- The split context must name this hook as `context.split.hook`.
- The group ID must be the payout group for `context.token`.

## Custody

- After a successful split, the hook should not retain input-token residue attributable to that split.
- Router-refunded input residue is added back to the source project through the source terminal.
- The hook does not expose an owner-controlled sweep path.

## Routing

- The router metadata target is the immutable router terminal.
- The output token is exactly `address(context.split.beneficiary)`.
- `address(0)` is never accepted as an output token.

## Accounting

- ERC-20 input amount is measured by hook balance delta after pulling from the source terminal.
- Native input amount must equal `msg.value`.
- ERC-20 allowances granted by the hook to the router and source terminal are cleared after use.

## Reentrancy

- `processSplitWith` is non-reentrant.
- Nested router callbacks cannot process a second split through the same hook execution.
