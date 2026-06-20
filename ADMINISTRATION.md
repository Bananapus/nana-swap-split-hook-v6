# Administration

## Deployment

Deploy `JBSwapSplitHook` with:

- the canonical `JBDirectory`,
- the canonical `JBRouterTerminal` for the chain.

The contract is ownerless after deployment.

## Project Configuration

For each source token a project wants to rebalance:

1. Add a payout split in group `uint256(uint160(sourceToken))`.
2. Set `hook = JBSwapSplitHook`.
3. Set `beneficiary = outputToken`.
4. Set an appropriate payout limit.
5. Configure the hook as feeless for the project.
6. Prefer `ownerMustSendPayouts = true` and grant payout permission only to intended automation.

## Native Token Target

Use `JBConstants.NATIVE_TOKEN` for native ETH output. Do not use `address(0)`.

## Emergency Handling

The hook has no admin rescue function. If a split is misconfigured, update the next ruleset's split configuration or
disable payout execution by removing the relevant permission/automation path.
