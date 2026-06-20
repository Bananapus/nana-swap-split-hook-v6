# User Journeys

## Repo Purpose

This repo provides a split-hook based treasury rebalance adapter. It lets a project route payout split funds from one
accepted accounting context into another accepted accounting context using the router terminal.

## Primary Actors

- project operators configuring payout splits and feeless status
- keepers or governance agents calling `sendPayoutsOf`
- auditors checking custody, refund, and authorization behavior

## Journey 1: Configure ETH -> USDC Rebalancing

**Actor:** project operator.

**Intent:** convert a bounded amount of ETH balance into USDC balance.

**Main Flow**

1. Add both native ETH and USDC accounting contexts to the project.
2. Configure an ETH payout split whose hook is `JBSwapSplitHook`.
3. Set the split beneficiary to the USDC token address.
4. Configure the ETH payout limit for the amount that may be rebalanced.
5. Mark the hook feeless for the project.
6. Call `sendPayoutsOf(projectId, JBConstants.NATIVE_TOKEN, amount, currency, minTokensPaidOut)`.

**Postconditions**

- ETH leaves the project's ETH balance through the payout split.
- The router swaps into USDC.
- USDC is added back to the same project balance.

## Journey 2: Configure USDC -> ETH Rebalancing

**Actor:** project operator.

**Intent:** convert USDC treasury balance back into native ETH.

**Main Flow**

1. Configure a USDC payout split whose hook is `JBSwapSplitHook`.
2. Set the split beneficiary to `JBConstants.NATIVE_TOKEN`.
3. Configure the USDC payout limit.
4. Trigger `sendPayoutsOf` for USDC.

**Postconditions**

- USDC is routed through the router.
- Native ETH is added to the project balance.

## Journey 3: Handle Partial Fills

**Actor:** keeper.

**Intent:** execute a swap where the router uses less than the full input.

**Main Flow**

1. Trigger the payout split.
2. Let the router refund unspent input to the hook.
3. The hook adds the residue back to the source project balance.

**Postconditions**

- Output token is credited for the consumed input.
- Unspent input token is credited back to the source accounting context.
