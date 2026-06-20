# Runtime Reference

## Split Encoding

- Input token: `context.token`
- Output token: `address(context.split.beneficiary)`
- Valid group: `uint256(uint160(context.token))`

## Router Metadata

The hook builds a router-scoped metadata entry:

```solidity
routeTokenOut = address(context.split.beneficiary)
```

The metadata target is the immutable router terminal supplied at construction.

## Events

`SwapSplit(projectId, terminal, tokenIn, tokenOut, amountIn, returnedAmountIn, caller)` is emitted after successful
routing. The output amount is observable from the downstream terminal's `AddToBalance` event.
