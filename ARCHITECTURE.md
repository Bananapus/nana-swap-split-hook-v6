# Architecture

## Scope

`JBSwapSplitHook` is deliberately narrow. It does not own a rules engine, keeper registry, treasury policy, or swap
implementation. It is the adapter between Juicebox payout splits and the existing router terminal.

## Components

- `JBSwapSplitHook`: stateless split hook. Verifies terminal callers, accepts split funds, routes through the router,
  and returns unspent input residue.
- `JBRouterTerminal`: external dependency. Discovers the route, performs the swap, and adds the output token to the
  project balance.
- `JBDirectory`: external dependency. Used only to verify that `msg.sender` is a terminal of the source project.

## Data Model

The hook has no mutable configuration.

Immutable constructor inputs:

- `DIRECTORY`
- `ROUTER_TERMINAL`

Split encoding:

- `context.token`: input token.
- `context.groupId`: must equal `uint256(uint160(context.token))`.
- `context.split.beneficiary`: output token.

## Flow

For ERC-20 payout splits, the terminal grants the hook a temporary allowance. The hook pulls the allocation, grants the
router a temporary allowance, and clears it after routing. For native-token payout splits, the terminal pushes ETH as
`msg.value`.

If the router returns unspent input tokens after a partial fill, the hook immediately adds those tokens back to the
source project through the source terminal. Residue is measured against the hook's pre-call balance so forced or stale
balances are not swept into the current rebalance.

## Trust Boundaries

The hook trusts:

- the source terminal's split accounting and temporary transfer semantics,
- the router terminal's route discovery, slippage enforcement, and final add-to-balance behavior,
- the directory's terminal membership view.

The hook does not trust arbitrary callers, ERC-20 nominal transfer amounts, or router refund behavior. It uses balance
deltas for incoming ERC-20s and handles both ERC-20 and native input residue.
