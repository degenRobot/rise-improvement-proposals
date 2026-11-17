---
rip: 3
title: Contract signatures on the hosted API
description: The RISEx API accepts and relays ERC-1271 signatures for order, cancel and leverage permits
author: degenRobot (@degenRobot, https://mattsmart.xyz)
discussions-to: To be opened with RISE
status: Draft
type: Standards Track
category: Interface
created: 2026-11-17
requires: ERC-1271, ERC-6492
---

> Numbering note: RISE publishes [RIP-1](https://docs.risechain.com/docs/risex/rips/rip-1) and [RIP-2](https://docs.risechain.com/docs/risex/rips/rip-2). This draft takes the next free number; RISE assigns the final one.

## Abstract

The hosted API at `api.rise.trade` should accept a permit whose `signer` is a contract and whose `signature` is longer than 65 bytes. It should check the permit by calling the account's `isValidSignature`, then relay it through the router's existing ERC-1271 permit path. Nothing changes on chain: `RISExAuthorization` already validates contract signatures, and the router already decodes ERC-1271 permits.

## Motivation

Today a contract account can hold collateral on RISEx and validate signatures on chain, but it cannot trade through the API under its own rules. We measured this on 13 November 2026 against the live testnet API:

- The API refused a 388-byte ERC-1271 envelope before relaying it, even though the account's own `isValidSignature` accepted it. The error was `invalid permit: signature must be 64 (compact) or 65 (r+s+v) bytes, got 388`.
- The API relayed a 65-byte ECDSA signature with `permit.signer` set to the account, and the router reverted `SignerNotAuthorized(<recovered key>)`. The API always recovers an ECDSA key, so the account's code is never consulted.

RISE's [integration reference](https://developer.rise.trade/reference/integration.md) says the same: an account that cannot produce an ECDSA signature must register a session key. RISEx checks a session key itself, without asking the account, so every rule the account wants to enforce is skipped on the API path. That includes the `_beforeOrder` hooks in [RIP-1](https://docs.risechain.com/docs/risex/rips/rip-1), which run only when an order passes through the sub-account.

The gap shows in who trades, and how. On 17 November 2026 we sampled the 2,090 mainnet accounts that had registered a signer in the previous 7 days or spent an OperatorHub allowance in the previous day. 2,085 were plain EOAs. Five were EIP-7702 smart wallets, all delegated to the same Porto `IthacaAccount`, and none was a standalone contract. Five is a floor: the sample only finds a smart wallet in the week it registers a new key.

The smart wallets do trade, but not as themselves. We traced one. It registered a 7-day session key through a wallet intent. The key is a plain EOA holding `Permission.All`, and every order after that carried the key's ECDSA signature. The wallet's own checks never saw an order. Multisig treasuries and lending protocols are in the same position: a session key is the only way in, and it leaves their rules behind.

It also affects RISE's own wallet. The RISE Wallet Stack is [built on Porto](https://x.com/degenRobot/status/1993652483152068697): passkey login through EIP-7702 and session keys with scoped permissions. A passkey signs with P-256 and cannot produce the secp256k1 signature the API demands. So today a RISE Wallet user who wants to trade on RISEx must first register a separate, unrestricted session key, and the wallet's own permission model stops at the API's door.

## Specification

The key words MUST, SHOULD and MAY are used as in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119).

1. **Signature length.** For `POST /v1/orders/place` and the cancel, cancel-all and leverage requests, `permit.signature` MUST accept any length from 64 bytes up to `MAX_SIGNATURE_BYTES`. We suggest 2,048 bytes; the credit account envelope in the examples is 388.
2. **Signature type.** The permit gains an optional field `signatureType`: `"ecdsa"` (the default, today's behaviour) or `"erc1271"`. With `"erc1271"`, the API MUST NOT recover a key from the signature and MUST treat `permit.signer` as the account.
3. **Pre-check.** Before relaying, the API MUST simulate the check `RISExAuthorization` runs on chain: `isValidSignature(digest, signature)` on `permit.signer`, through the ERC-6492 universal validator, against the latest block, with a gas cap `MAX_1271_GAS`. Any result other than the magic value `0x1626ba7e` is a refusal.
4. **Relay.** A permit that passes is encoded as `PermitParamsV1ERC1271` and submitted through the router, exactly as RISEx's own relayers submit ERC-1271 permits today. The on-chain check runs again at inclusion and is authoritative.
5. **Errors.** The API MUST return distinct codes for `erc1271_invalid` (wrong magic value), `erc1271_reverted` and `erc1271_gas`, with the revert data where there is any. An account can then tell a policy refusal from a bug.
6. **Nonces.** A permit refused at the pre-check MUST NOT consume its nonce slot. Today a refused order still burns its slot, so clients have to journal before they POST.
7. **Session login.** `POST /v1/auth/login` and `register-signer` SHOULD accept the same `signatureType`. A contract account can then open a JWT session and register keys without an on-chain transaction.
8. **Quotas.** The API MAY count each pre-check against the account's existing per-address quota, and MAY apply a lower rate to `erc1271` permits.

```
client ──POST /v1/orders/place {permit, signatureType: "erc1271"}──> API
API    ──eth_call isValidSignature(digest, sig) on permit.signer, gas ≤ MAX_1271_GAS
          ├─ not 0x1626ba7e → 4xx erc1271_invalid / _reverted / _gas (nonce not consumed)
          └─ 0x1626ba7e     → relay through Router (PermitParamsV1ERC1271)
Router ──RISExAuthorization → isValidSignature again at inclusion (authoritative)
```

## What this unlocks

An account decides, in code, which orders count as its own. An order that breaks the account's rule is an invalid signature, and RISEx refuses it like any forged permit.

| Use | What the account checks in `isValidSignature` | Today |
| --- | --- | --- |
| **Credit accounts** ([example](../examples/credit-accounts.md)) | The order would not leave the loan under-collateralised: market and price-band policy, then line health after the order | Forced onto an on-chain gateway that needs the order role, or onto a session key with no pre-trade check |
| **Passkey smart wallets** ([examples](../examples/smart-wallets-and-more.md)): RISE Wallet, [Porto](https://github.com/ithacaxyz/porto), Coinbase Smart Wallet | A WebAuthn P-256 signature from the user's device, or a scoped app key inside its spend and expiry limits | P-256 keys cannot make a secp256k1 signature, so the wallet must mint a separate, unrestricted key |
| **Multisig and treasury accounts** (Safe) | M-of-N owner signatures | Can trade only through a session key that one person holds, which bypasses the M-of-N policy |
| **RIP-1 sub-accounts** | The builder's `_beforeOrder` logic | Bypassed whenever the account trades through a session key |
| **Delegated trading** ([example](../examples/hooks.md)) | An operator stays inside expiry, market, per-order and cumulative caps | Needs a gateway with the order role |
| **Prop and funded accounts** ([example](../examples/hooks.md)) | A daily loss limit, checked before any order that adds risk | Enforced only after the fact |
| **AI and bot agents** | The agent's key, plus a policy the owner set: size, leverage, markets | The agent holds an unrestricted Perps key |

**Credit accounts in numbers.** In the testnet experiment, an ERC-4626 pool lends USDC.e to a per-borrower account whose RISEx margin is the loan. With the pre-trade check in the signature, one adversarial order is bounded at about 5 USDC under the experiment's settings. With a session key instead, we measured two weaknesses on testnet. The key can raise leverage to the market maximum (50× on BTC and ETH, set live through `POST /v1/account/leverage`). And one crossed trade against an account the borrower controls can move the whole equity out in one block, bounded only by the debt.

**Porto as the pattern.** Porto is an EIP-7702 account whose keys are passkeys and scoped app keys, verified through ERC-1271. The project was [archived on 19 August 2026](https://github.com/ithacaxyz/porto), but RISE Wallet is built on the pattern it shipped: a passkey signer, permissioned app keys and 7702 delegation. None of it can reach RISEx's API today.

## Rationale

- **Why the API, not the contracts.** The router and `RISExAuthorization` already support ERC-1271 (the router's `extractPlacePermitERC1271` decodes these permits). Only the API's 64- or 65-byte check stands in the way, so the change is small and needs no contract upgrade.
- **Why signatures need to be long.** `isValidSignature` receives only the digest, and an account cannot read an order's market, side or size from a hash. So the signature carries the order's preimage: the account rebuilds the digest from it, checks that the two match, then checks the fields. The experimental credit account's envelope (a 4-byte tag, then the ABI-encoded order preimage and the signer's 65-byte signature) is 388 bytes. The match also means the envelope cannot authorise any other RISEx message.
- **Why an explicit `signatureType`.** Inferring the type from the length, or from whether `signer` has code, breaks for EIP-7702 accounts. They have code and can also produce 65-byte ECDSA signatures.
- **Why a pre-check at all.** Without one, every invalid contract signature becomes a reverted relayer transaction that RISE pays for.
- **Why not session keys.** Session keys are the right tool for speed, but they move the policy out of the account. An account that wants both can register a key for routine orders and still sign high-risk actions itself.

## Backwards compatibility

Fully compatible. Requests without `signatureType` behave exactly as today, and existing ECDSA and session-key flows are untouched.

## Reference implementation

- **Account side.** The experimental credit account validates each order inside `isValidSignature`: it checks the signer's role, then the order policy (markets, IOC limit inside a 10 bp band, size caps), then the account's line health after the order. On testnet its own check accepted the 388-byte envelope. [examples/credit-accounts.md](../examples/credit-accounts.md#in-code) quotes the function.
- **Venue side.** The router's existing ERC-1271 permit decoding, and `RISExAuthorization`'s call through the ERC-6492 validator.

## Security considerations

The main new risk lands on RISE's infrastructure, not on the exchange: the API starts running code that accounts wrote. The on-chain trust model does not change, because `RISExAuthorization` already accepts these signatures.

| Risk | What could go wrong | Mitigation |
| --- | --- | --- |
| **Cost and denial of service** | An account's `isValidSignature` burns gas or loops, and a flood of permits ties up the API's RPC capacity | `MAX_1271_GAS` cap; count pre-checks against the per-address quota; a lower rate for `erc1271` |
| **Check passes, then fails on chain** | Validation reads state (price, health, time). It passes at the pre-check and reverts at inclusion, and RISE's relayer pays for the failed transaction. A hostile account can do this on purpose | Throttle or suspend accounts whose on-chain failure rate is high; keep each order in its own call so one failure cannot revert a batch |
| **Check fails, then would have passed** | A state-dependent account sees spurious refusals at busy moments | Return the revert data (spec item 5); accounts should avoid checks that depend on the exact block |
| **Weak account code** | An account returns the magic value for everything, or accepts its signer's signature over a bare hash. A signature made for one such account is then valid for every other account with the same signer, which is the replay ERC-7739 exists to stop | Recommend ERC-7739 nested typed data in RISE's docs; the API passes the bytes through untouched |
| **Whoever the account accepts can withdraw** | `permitTransferFrom` pays any recipient on the account's signature, so a signer set that is too broad (a keeper key, say) can move all funds. This is true on chain today; more accounts will now meet it | Document it next to the feature: keepers belong in scoped session keys, never in the ERC-1271 signer set |
| **Upgradeable accounts** | The account's rules can change after a user deposits | Out of RISE's scope, but the API could show whether `signer` is a proxy |
| **Latency and fairness** | One extra `eth_call` per order adds a round trip, so contract accounts are slightly slower than EOAs | Acceptable for policy-checked flow; accounts that need speed keep a session key |
| **Truncation or parsing bugs** | An API that silently cuts long signatures, or misreads the type field, relays the wrong bytes | Reject over-length input outright; fuzz the decoder against the router's own `extractPermitERC1271` |

Liquidation is unaffected. RISEx's liquidator does not need the account's signature, so no `isValidSignature` can block it.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE).
