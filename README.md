# nana-swap-split-hook-v6

`JBSwapSplitHook` is a Juicebox payout split hook that swaps the split's terminal token into another token, then adds
the output back to the same project's balance through a configured `JBRouterTerminal`.

The intended use is treasury rebalancing between accounting contexts, for example ETH -> USDC or USDC -> ETH, without
an operator wallet or treasury manager custodying the funds between withdrawal and deposit.

## How It Works

Configure a payout split whose `hook` is `JBSwapSplitHook`.

The split's `beneficiary` field is interpreted as the output token:

- `beneficiary = USDC` means swap the split amount into USDC.
- `beneficiary = JBConstants.NATIVE_TOKEN` means swap the split amount into native ETH.
- `beneficiary = tokenIn` routes the funds back into the same token as a no-op add-to-balance.

When a terminal processes the payout split, the hook:

1. Verifies the caller is a terminal of the source project.
2. Verifies the split group matches the incoming payout token.
3. Accepts the split allocation.
4. Builds router metadata with `routeTokenOut = split.beneficiary`.
5. Calls `JBRouterTerminal.addToBalanceOf(...)`.
6. Adds any router-refunded input residue back to the source project's original token balance.

## Operational Notes

The hook should be configured as feeless for projects that use it for treasury rebalancing. Otherwise the core terminal
treats the split as an ordinary payout to a non-feeless hook and deducts the standard terminal fee before the swap.

Use `ownerMustSendPayouts = true` and grant `SEND_PAYOUTS` to the automation address or hook-driven keeper surface you
intend to use. A misconfigured or reverting split can still consume payout-limit capacity while refunding funds to the
project balance.

## Development

```bash
forge test
```

Fork tests use `RPC_ETHEREUM_MAINNET` and skip when the variable is unset.
