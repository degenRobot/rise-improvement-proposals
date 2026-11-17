---
rip: 4
title: Whitelisting contracts for the order role
description: A public process to apply for, receive, review and lose AccessManager role 14 for a contract
author: degenRobot (@degenRobot, https://mattsmart.xyz)
discussions-to: To be opened with RISE
status: Draft
type: Meta
created: 2026-11-17
requires: 3
---

> Numbering note: RISE publishes [RIP-1](https://docs.risechain.com/docs/risex/rips/rip-1) and [RIP-2](https://docs.risechain.com/docs/risex/rips/rip-2). This draft takes the next free number after [RIP-3](rip-3.md); RISE assigns the final one.

## Abstract

RISEx gates on-chain trading behind AccessManager role 14 (`TRADE_SUBMITTER`): placing and cancelling orders and changing leverage or margin mode, on PerpsManager and through the router. This RIP defines how a third-party contract applies for that role, the tiers it passes through from testnet to mainnet, what it must show at each tier, how the grant is made, and when it is revoked.

## Motivation

Some designs need to place an order and change their own state in the same transaction. They cannot work through the API, even with [RIP-3](rip-3.md), because the API submits the order in a separate transaction that the contract does not control.

Today role 14 is held only by RISEx infrastructure: the router, OperatorHub and the relayer EOAs (39 on mainnet when we counted on 30 October 2026). On 13 November 2026 RISE granted it, on request and with zero execution delay, to three experimental contracts on testnet: a synthetic book, a hook gateway and a credit order gateway. Every path that had been waiting on it ran live the same day. That worked, but there is no published route for anyone else: no stated criteria, no mainnet path and no revocation policy. Builders cannot plan around a grant they cannot predict.

RISE's own drafts wait on the same role. [RIP-1](https://docs.risechain.com/docs/risex/rips/rip-1) gives a sub-account `_beforeOrder` and `_afterOrder` hooks around its orders. [RIP-2](https://docs.risechain.com/docs/risex/rips/rip-2) says a portfolio-margin liquidation happens "in a single atomic transaction". Both need the sub-account to place an order on chain, and it cannot: on mainnet on 17 November 2026, `canCall` returned false on `PerpsManager.placeOrder` for an address without role 14.

On a fork, an account of the same kind closed its perp, withdrew and repaid its Morpho loan in one call once it held the role ([portfolio margin liquidation](../examples/portfolio-margin.md)).

This is the composability argument for building the exchange on its own chain ([Unleash the Money Legos](https://x.com/degenRobot/status/1995836883721748807), [Why build both the chain and the exchange](https://x.com/degenRobot/status/2011455021616083304)). Order books become a money lego only when other contracts can trade on them in the same transaction. Role 14 is the switch that turns that on, so the process for flipping it should be public.

The grant brings RISE order flow without the risk behind it. A holder's orders arrive as ordinary orders under a builder code: the synthetic book rests one post-only order at the mid and sends its market closes and liquidations to RISEx's book. The leverage the book offers stays in its own pool.

On a fork, four traders ran at 94× inside the book while RISEx saw one account at 4×. A 3% gap bankrupted all four and cost the pool 8%, and the account's equity was still 17 times RISEx's maintenance margin ([where the leverage risk sits](../examples/synthetic-book.md#where-the-leverage-risk-sits)). One limit: trades matched between two of the book's own traders never reach RISEx, so the venue gets the book's net flow, not its gross.

## Specification

The key words MUST, SHOULD and MAY are used as in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119).

### Application

An applicant submits, publicly (a forum post, or a pull request to a RIPs repository):

- Proxy and implementation addresses, verified source, and who holds the upgrade and admin keys (timelock length, multisig threshold).
- Every RISEx function the contract calls, and for which accounts: only itself, or other accounts through router permits.
- Who may make the contract trade, and what stops them exceeding their limits.
- How a position is closed if the contract's own logic fails, and whether a reduce-only order can ever be blocked.
- Expected order rate and peak notional.
- Fork tests against RISEx (testnet tier) and an audit report (mainnet tiers).

### Tiers

| Tier | Grant | Required to enter | Limits while in it |
| --- | --- | --- | --- |
| 0. Fork | None; tests write AccessManager storage | Nothing | Local only |
| 1. Testnet | `grantRole(14, proxy, 0)` on testnet | Application, verified source, passing fork tests | Expires after 90 days unless renewed |
| 2. Mainnet, capped | `grantRole(14, proxy, 0)` on mainnet | 30 days on testnet without incident; an audit; upgrade admin behind a timelock of at least 48 hours | Notional and order-rate caps agreed with RISE; builder code required |
| 3. Mainnet | Same grant, caps lifted | 90 days at tier 2 without incident | Standing review on every upgrade |

The durations and caps above are starting proposals for RISE to set.

### The grant

The execution delay MUST be zero. We showed on a fork that a delayed grant is the same as no grant. `canCall` returns `false 3600`, the call reverts `AccessManagerNotScheduled`, and router calldata carries a nonce and a five-minute deadline, so a scheduled copy could never match. RISE MAY instead set a grant delay on the role, so that a new member is announced on chain before it takes effect.

```solidity
// RISE's AccessManager admin
accessManager.grantRole(14, proxy, 0);   // executionDelay must be 0

// The applicant's check. hasRole alone is not enough: it is true for a delayed grant too.
(bool allowed, uint32 delay) =
    accessManager.canCall(proxy, perpsManager, IPerpsManager.placeOrder.selector);
require(allowed && delay == 0);
```

### Registry

RISE publishes a page listing every contract that holds role 14: address, owner, purpose, tier, date granted and audit link. `RoleGranted` and `RoleRevoked` events are the source of truth.

### Upgrades

An upgrade of a tier 2 or tier 3 contract MUST be announced before it executes. RISE SHOULD watch `Upgraded` events and suspend any unannounced upgrade.

### Revocation

RISE revokes with `revokeRole(14, proxy)`, effective at once, on any of: an exploit or a loss traced to the contract; an unannounced upgrade; a breach of agreed caps; the owner's request. The owner gets notice, and the reason goes in the registry.

## What this unlocks

The first three ran live on RISE testnet after the 13 November grant. The fourth ran on a fork of RISE mainnet.

| Design | Why it needs the role | Evidence |
| --- | --- | --- |
| **Synthetic book** ([example](../examples/synthetic-book.md)) | Traders match each other at the RISEx mid inside the contract. The unmatched side waits in a queue mirrored by one resting post-only order on RISEx, which must be placed, re-priced or cancelled in the same transaction that changes the queue | ETH book upgraded to the queue design on 13 November; open, resting fill, settlement, a match between two traders and market closes ran live |
| **Hooks** ([example](../examples/hooks.md)) | A gateway runs the account's `beforeOrder` checks, places the order, then runs `afterOrder`, which can revert the fill: pre- and post-trade checks in one atomic call | An allowed order filled; an oversized order was refused on chain (`OrderTooLarge`); a reduce-only close skipped the hooks |
| **Credit liquidation** ([example](../examples/credit-accounts.md)) | The liquidator's reduce-only closes run on chain through the gateway, under the same policy as the borrower's orders, so a keeper can liquidate with no dependency on the API | Live on testnet, full drill: health line 0.9985 → `startLiquidation` → close → `liquidate`; debt repaid in full |
| **Portfolio margin liquidation** ([example](../examples/portfolio-margin.md)) | An account that borrows against collateral and trades the loan (RIP-2's design) has to close the perp, withdraw and repay in one transaction, or the loan is exposed between the steps. The liquidator's close is an ordinary reduce-only order, so RISEx's margin check and its own liquidator are not changed | Mainnet fork, 17 November: one call closed 0.2 ETH, withdrew 499.69 USDC and repaid it against a 500.00 debt, at a moment when RISEx's liquidator refused the account as healthy. Without the role the same call reverted |

Other designs the role would enable:

- Liquidation-protection keepers, which RIP-1 lists as a use: a keeper closes part of an account's position before RISEx's liquidator would, in one call.
- A money-market liquidator that seizes WETH on Morpho and shorts the same size on RISEx in the same transaction, so it carries no price risk while it sells the collateral.
- A delta-neutral vault that takes a deposit and opens its short before the transaction ends, so it is never unhedged between the two.
- On-chain take-profit, stop-loss and TWAP executors.
- Intent solvers that fill a user's order and hedge on RISEx in the same block.

Where RIP-3 is enough, builders should prefer it. A hook's pre-trade checks could move into an account's `isValidSignature` under RIP-3. The after-trade checks and the synthetic book cannot, because they act on the result of the fill.

## Rationale

- **Why tiers.** A contract with role 14 skips the API's rate limits and any off-chain screening the API applies. Tiers let RISE watch real behaviour at small size before it trusts large size.
- **Why zero execution delay, with a grant delay.** An execution delay breaks every order (see "The grant"). A grant delay gives the same public notice without that cost.
- **Why a narrower role is worth considering.** Role 14 covers the router and PerpsManager alike. Most applicants need only `PerpsManager.placeOrder` and `cancelOrder` for their own account. A separate role scoped to those selectors would cut what a compromised holder can reach.

## Backwards compatibility

No code change. Existing role holders keep their grants, and RISE's own infrastructure is out of scope.

## Reference implementation

Three experimental contracts on RISE testnet, each granted role 14 on 13 November 2026:

- The synthetic queue book ([examples/synthetic-book.md](../examples/synthetic-book.md)).
- The hook gateway and its gateway-only sub-account ([examples/hooks.md](../examples/hooks.md)).
- The credit order gateway ([examples/credit-accounts.md](../examples/credit-accounts.md)).

Their fork tests grant role 14 by writing AccessManager storage, which is the tier 0 harness.

## Security considerations

**What the role reaches.** On mainnet on 17 November 2026 (block 27,294,719), AccessManager's `getTargetFunctionRole` returned 14 for `placeOrder`, `cancelOrder`, `cancelOrders`, `updateLeverage` and `updateMarginMode` on PerpsManager, and for `placePerpsOrder`, `cancelPerpsOrder` and `updatePerpsLeverage` on the router. An October reading of the same contracts also put `updateIsolatedPositionMarginBalance` and the router's spot entry points under it. We have not re-checked those two.

**What it does not reach.** Role 14 does not let a holder trade someone else's account. In the RISEx source we have (a February 2026 snapshot), `PerpsManager.placeOrder` trades for `_msgSender()`, so a direct caller trades only its own account. Through the router, every order still needs the account's valid permit. Both held on a mainnet fork on 17 November: a holder that appended another account's address to its calldata traded nothing for that account, and the router refused a permit signed by the wrong key.

So the risks are what a holder can do with its own account, what it can do with accounts that chose to trust it, and what it does to RISE's infrastructure.

| Risk | What could go wrong | Mitigation |
| --- | --- | --- |
| **Bypassing API limits** | On-chain orders skip the API's 200-requests-per-10-seconds edge limit, the per-address quota and any screening the API does | Tier 2 caps on order rate and notional; RISE watches the holder's on-chain order rate |
| **Compromised or malicious upgrade** | An upgradeable holder is swapped for code that trades its pooled funds into an accomplice's orders, or spams the book | Timelocked upgrade admin; announced upgrades; RISE suspends on an unannounced `Upgraded` event |
| **Trust concentrates in the holder** | Accounts that defer to a gateway (the hook experiment's sub-account is valid only for digests the gateway approved) are all exposed if the gateway is | The applicant states who can make it trade and the limits; an audit at tier 2 |
| **A holder relays someone else's signed order** | Any holder can submit a valid signed payload before its deadline, not only RISE's relayers (shown on a fork). As the role spreads, a payload that leaks can be timed by more parties | Permit deadlines stay short (five minutes today); holders accept no payloads from outside; the narrower role in the Rationale has no router access |
| **Risk moves to the holder's pool** | A book or a margin product offers leverage or collateral that RISEx would not, and losses past a trader's margin fall on the holder's pool. If that pool runs out, the holder's RISEx account is one large ordinary account for RISEx's liquidator | The applicant states pool size against open interest and the gap that would empty it; tier 2 notional caps; RISEx's margin check on the holder's account is unchanged |
| **A third-party liquidator is late** | A margin product's own trigger fires after RISEx's maintenance line. RISEx's liquidator acts first, and the product's loan is left to its collateral alone. Past RISEx's takeover line only its reserve vault can take the position (`AccountMustBeTakenOverByRLP` on a fork) | The applicant shows its trigger sits ahead of RISEx's at every leverage it allows |
| **Pooled client funds** | A synthetic book holds every LP's money in one RISEx account, so a bug or an exploit hits all of them, and RISEx sees one account where there are many clients | Disclose pooling in the application; per-book caps; RISE's written consent for pooled flow on mainnet |
| **Blocked closes** | The holder's logic stops a reduce-only order, leaving users unable to exit | Required: reduce-only orders and cancels never pass through optional logic. The experimental hook gateway skips hooks for them and checks that the close did not grow the position |
| **Silent zero fills** | RISEx IOC orders do not revert on zero fill, so a contract that assumes a fill can book a trade that never happened. Seen live on testnet when the BTC book had no bids within 8% of mark | Required test: read the position after every order and treat a zero fill as failure |
| **Order ID reuse** | RISEx deletes filled and cancelled orders and reuses their IDs, so a contract tracking an ID can act on someone else's later order | Required test: track fills by position, not by order ID |
| **Ordering and MEV** | A holder that sees its queue and submits in the same block can be front-run, or front-run others | Price from RISEx's mark or mid; bound slippage with limit prices |
| **Revocation strands state** | Revoking the role mid-flight leaves a resting order on RISEx and positions the contract can no longer manage | The applicant shows a wind-down path that works without the role: cancels and closes through a session key or the API, or an order expiry on every resting order |
| **Delayed grant** | A grant with an execution delay looks granted, but every call reverts | Zero execution delay (see "The grant"); clients check that `canCall` returns `true 0`, not just `hasRole` |

## Copyright

Copyright and related rights waived via [CC0](../LICENSE).
