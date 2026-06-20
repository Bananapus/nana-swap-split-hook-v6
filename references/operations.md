# Operations Reference

## ETH -> USDC

Configure the ETH payout split:

- `hook = JBSwapSplitHook`
- `beneficiary = USDC`
- `groupId = uint256(uint160(JBConstants.NATIVE_TOKEN))`

Then call `sendPayoutsOf` on the source terminal for the native token.

## USDC -> ETH

Configure the USDC payout split:

- `hook = JBSwapSplitHook`
- `beneficiary = JBConstants.NATIVE_TOKEN`
- `groupId = uint256(uint160(USDC))`

Then call `sendPayoutsOf` on the source terminal for USDC.

## Checklist

- Both tokens are accepted accounting contexts for the project.
- The router terminal can route between the tokens.
- The hook is feeless for the project.
- Payout limits cap the maximum amount per cycle.
- Automation has only the permissions it needs to call `sendPayoutsOf`.
