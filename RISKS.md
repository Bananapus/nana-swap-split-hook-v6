# Risks

## Fee Configuration

If the hook is not marked feeless for a project, the terminal deducts the standard payout fee before calling the hook.
For treasury rebalancing this is usually unintended. Operators should configure the hook as feeless for each project
that uses it as an internal rebalance path.

## Payout Limit Consumption

This hook runs inside `sendPayoutsOf`. Even when a router call reverts and the core split machinery refunds the source
funds, payout-limit capacity may be consumed. Use `ownerMustSendPayouts` and narrow permissions so arbitrary callers
cannot grief a rebalance split.

## Output Token Encoding

The split beneficiary is the output token address. For native ETH, use `JBConstants.NATIVE_TOKEN`, not `address(0)`.
`address(0)` is rejected.

## Router Quote Safety

The hook supplies `routeTokenOut` metadata but does not manufacture an on-chain `pay` quote. This preserves the router's
strict `addToBalanceOf` behavior: V3 TWAP and supported V4 oracle routes can execute automatically; vanilla V4 spot
routes that need a manipulation-resistant quote should revert.

## Fee-On-Transfer Tokens

The hook routes the amount it actually receives, not the nominal split amount. Transfer fees taken on the way from the
terminal to the hook or from the hook to the router are not recoverable by the hook.

## Same-Token Routes

If `beneficiary == context.token`, the router performs an add-to-balance route without a swap. This is allowed so a bad
target does not strand funds in the hook, but it still consumes payout machinery and should not be used as a routine
configuration.

## Forced Funds

The hook is stateless and has no owner rescue function. Forced ETH or direct ERC-20 transfers are intentionally outside
the split flow. Split processing only returns input-token residue attributable to the current call.
