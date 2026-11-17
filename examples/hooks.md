# Hooks: pluggable checks before and after every order

**Needs:** [RIP-4](../RIPs/rip-4.md) for the full design; [RIP-3](../RIPs/rip-3.md) covers the pre-trade half. **Status:** live on RISE testnet since 13 November 2026. **PDF:** [contract-accounts.pdf](contract-accounts.pdf).

A hook gateway lets any RISEx account attach its own rules to its orders. The account registers hook contracts with the gateway; every order that can add risk runs them in one transaction:

```
caller ──> HookGateway.placeOrder(account, order, hookData[])
             │ account.isTrader(caller)?              owner or operator
             │ hook[0..n].beforeOrder(ctx, data)      may revert
             │ approve the permit digest for this account (transient)
             │ router.placePerpsOrder(ERC-1271 permit, signer = account)
             │     └─ RISEx → account.isValidSignature → was this digest approved by the gateway?
             │ clear the approval
             │ hook[0..n].afterOrder(ctx, orderId, sizeBefore, sizeAfter, data)   may revert, undoing the fill
```

Reduce-only orders and cancels call no hooks, and the gateway checks that a reduce-only order did not grow the position. No hook can stop a close.

The account itself has no ECDSA key, no session keys and no OperatorHub allowance. Its `isValidSignature` is valid only for the digest the gateway approved for it during the gateway's own router call. So the only way to trade it is through its hooks.

## In code

A hook is two functions. The gateway calls the first before it places the order and the second after, with the position on either side of the fill:

```solidity
interface IOrderHook {
    function beforeOrder(OrderContext calldata ctx, bytes calldata hookData) external;
    function afterOrder(OrderContext calldata ctx, uint56 orderId, int256 sizeBefore,
                        int256 sizeAfter, bytes calldata hookData) external;
}
```

The risk-cap hook's pre-trade check is a few lines:

```solidity
function beforeOrder(OrderContext calldata ctx, bytes calldata) external view onlyGateway {
    uint256 cap = caps[ctx.account].maxOrderNotional;
    uint256 n = orderNotional(ctx);
    if (cap != 0 && n > cap) revert OrderTooLarge(n, cap);
}
```

And the account refuses every signature except the one the gateway is presenting for it:

```solidity
function isValidSignature(bytes32 hash, bytes calldata) external view returns (bytes4) {
    if (hash != bytes32(0) && gateway.approvedDigest(address(this)) == hash) return 0x1626ba7e;
    return 0xffffffff;
}
```

## Example hooks

| Hook | Before the order | After the order |
| --- | --- | --- |
| Risk cap | Refuses an order above a notional cap | Refuses a fill that leaves the traded market above a leverage cap |
| Daily loss | Refuses risk-adding orders once a funded account has lost its daily limit | |
| Delegate cap | An operator trades only before an expiry, in allowed markets, inside per-order and cumulative caps | |

## What these make possible

- **Prop and funded accounts.** A firm funds a trader's account and the daily-loss hook enforces the drawdown rule on chain, before the order, rather than by closing the account after the fact.
- **Delegated trading.** An owner lets a manager, a friend or a bot trade their account within limits that expire.
- **Vault mandates.** A copy-trading or managed vault constrains its manager to the markets and leverage it advertised.
- **Compliance rules.** An institution restricts which markets and sizes an account may touch.

## What ran live on RISE testnet

| Case | Result |
| --- | --- |
| Allowed order | Filled |
| Oversized order | Refused on chain by the risk-cap hook (`OrderTooLarge`) |
| Reduce-only close | Skipped the hooks and filled |

## Why it needs the order role, and what RIP-3 would change

The gateway must place the order itself so that the after-hooks can see the fill and revert it. That needs RISEx's order role ([RIP-4](../RIPs/rip-4.md)).

With [RIP-3](../RIPs/rip-3.md), the before-hooks no longer need a gateway: the account can run them inside its own `isValidSignature` and trade through the hosted API like anyone else. After-hooks still need the gateway.

## Known limits

- After-hooks run in the transaction that places the order. A resting order that fills later never comes back through them, so the daily-loss hook cannot see that fill.
- The daily-loss hook counts deposits and withdrawals as profit or loss.
