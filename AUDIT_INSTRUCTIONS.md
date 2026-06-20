# Audit Instructions

Focus areas:

- terminal caller validation through `JBDirectory.isTerminalOf`
- split group validation against the incoming token
- ERC-20 balance-delta accounting for fee-on-transfer inputs
- native-token `msg.value` accounting
- allowance cleanup after router and terminal calls
- input residue return after router partial fills
- preservation of router slippage behavior by avoiding self-generated quotes
- reentrancy through router calls or token callbacks

Primary tests:

```bash
forge test
```

Fork tests use:

```bash
RPC_ETHEREUM_MAINNET=... forge test --match-path 'test/fork/**'
```
