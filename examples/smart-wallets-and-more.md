# Smart wallets and other things contract signatures unlock

**Needs:** [RIP-3](../RIPs/rip-3.md). **PDF:** [contract-accounts.pdf](contract-accounts.pdf).

Under RIP-3, an account's `isValidSignature` becomes the place where it decides which orders are its own, and RISEx's hosted API respects that decision. Anything a contract can check, an account can require before it trades. This page lists what that opens up beyond the experiments on the other pages. None of these is built here; they are the uses we expect.

## Smart wallets

| Wallet | What it signs with | What RIP-3 changes |
| --- | --- | --- |
| **RISE Wallet** ([built on Porto](https://x.com/degenRobot/status/1993652483152068697)) | Passkeys (Face ID, Touch ID) through EIP-7702, plus session keys with scoped permissions | A user can trade RISEx with the passkey or a scoped wallet key, inside the limits the wallet already enforces, rather than minting a separate unrestricted Perps key |
| **[Porto](https://github.com/ithacaxyz/porto)** (archived August 2026) | WebAuthn P-256 passkeys and permissioned app keys, verified through ERC-1271 | Porto shipped passkey and app-key signing through ERC-1271. An account built this way could sign a RISEx permit as it stands |
| **Coinbase Smart Wallet** | Passkeys | A user trades with the passkey they already have, with no second key to mint, store or lose |
| **Safe** | M-of-N owners | A treasury or fund can trade RISEx with its multisig policy intact, including a threshold that rises with order size |

The common problem: a passkey signs with the P-256 curve, and the API only recovers secp256k1 keys. Today every passkey wallet has to create a second key just for RISEx, and that key carries none of the wallet's limits.

## Accounts with rules

Each of these is an `isValidSignature` that checks the order against a policy before saying yes.

| Feature | What the account checks |
| --- | --- |
| **Spending and loss limits** | Daily notional, daily loss, maximum leverage, allowed markets |
| **Agent wallets** | An AI or bot agent's key may trade, but only inside the size, leverage, market and expiry limits its owner set. The agent never holds an unrestricted key |
| **Copy trading and managed vaults** | The leader's or manager's order fits the vault's published mandate |
| **Funded and prop accounts** | The trader is inside the firm's drawdown rules before any risk-adding order |
| **Under-collateralised lending** | The order keeps a loan healthy ([credit accounts](credit-accounts.md)) |
| **Cross-protocol margin** | The account reads its own loan on a money market (Morpho, Aave) and refuses an order that would leave the combined position unsafe. Liquidating such an account in one transaction needs RIP-4 ([portfolio margin liquidation](portfolio-margin.md)) |
| **Institutional controls** | Only allow-listed signers, markets and sizes; large orders need a second approver |
| **Recovery and inheritance** | The account's signer set can be rotated by guardians, and trading permissions follow, without RISEx having to know |

## Orders anyone can relay

An account can also approve orders by their content rather than by who sent them. The signature bytes carry the order's fields; the account rebuilds the digest from them, checks the match, and validates the order against conditions the owner stored earlier. No owner key signs at submit time, so anyone (a keeper, a solver, the user's own browser) can submit the order through the hosted API.

| Feature | The account accepts an order when |
| --- | --- |
| **Permissionless stop-loss and take-profit** | It is reduce-only, and the oracle mark has crossed the trigger the owner set |
| **TWAP and DCA** | It is the next slice of a schedule the owner approved: size, interval, price limit |
| **Rebalancing** | It moves the account's exposure back toward a target the owner set |
| **Deleveraging** | It is reduce-only and the account's own health is below a threshold, so any keeper can protect it before RISEx's liquidator would |

These need no new order types from RISEx. The venue sees an ordinary limit or IOC order with a valid signature; the condition lives in the account.

## What stays the same

- RISEx's liquidator still works on every account; no `isValidSignature` can block a liquidation.
- Session keys stay the fast path. An account can register one for routine orders and keep its own signature for the actions that matter.
- The risks RISE takes on, and how to bound them, are in [RIP-3's security considerations](../RIPs/rip-3.md#security-considerations).
