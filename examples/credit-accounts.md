# Credit accounts: lending to perps traders with the risk check inside the signature

**Needs:** [RIP-3](../RIPs/rip-3.md) (the intended design), or [RIP-4](../RIPs/rip-4.md) (the gateway variant that runs today). **Status:** gateway variant live on RISE testnet, including a full liquidation. **PDF:** [contract-accounts.pdf](contract-accounts.pdf).

This experiment lends USDC.e to perps traders on RISEx. Lenders deposit into one ERC-4626 pool. A borrower opens a credit account, a smart-contract RISEx account owned by a credit manager contract, adds USDC.e or pledges WETH or WBTC, and draws USDC.e that lands as the account's RISEx margin.

## The idea: an order that breaks the loan is an invalid signature

The borrower trades through RISEx, but every order is a permit the account itself validates through ERC-1271:

```
order permit ──> account.isValidSignature(digest, signature)
                   ├─ who signed? borrower, liquidator or keeper
                   ├─ order policy: allowed market, IOC limit inside a 10 bp band, size caps
                   └─ venue risk: would the loan still be healthy after this order?
                 → magic value, or refusal
```

An order that would leave the loan under-collateralised is never refused by an off-chain service that could be down or wrong. It is not a valid signature, and RISEx rejects it like a forgery.

### In code

The account's check, simplified to the place-order case:

```solidity
function isValidSignature(bytes32 hash, bytes calldata signature) public view returns (bytes4) {
    if (bytes4(signature[:4]) != ORDER_ENVELOPE_MAGIC) return 0xffffffff;
    OrderEnvelope memory e = abi.decode(signature[4:], (OrderEnvelope));

    // 1. Rebuild RISEx's digest from the order in the envelope. It must equal `hash`,
    //    so the envelope cannot approve any other message.
    if (_risexDigest(_witness(e)) != hash) return 0xffffffff;

    // 2. Who signed: the borrower, a liquidator or a keeper.
    SignerRole role = creditManager.signerRole(address(this), e.signer);
    if (role == SignerRole.None) return 0xffffffff;
    if (!SignatureCheckerLib.isValidSignatureNow(e.signer, hash, e.signature)) return 0xffffffff;

    // 3. Order policy, then the loan's health after the order. Reverts if either refuses.
    orderPolicy.checkPlaceOrder(address(this), role, uint88(e.data));
    return 0x1626ba7e;
}
```

`isValidSignature` receives only a hash, and a contract cannot read an order out of a hash. That is why the signature carries the order itself, and why it is 388 bytes long.

## Health and liquidation

The account's line is:

```
line = (max(equity, 0) × equityRatio + Σ pledge × weight) / debt
```

When the line drops below 1, anyone may call `startLiquidation`. The liquidator closes positions reduce-only, then `liquidate` withdraws the cash and the pledge, repays the gap (from the liquidator's USDC.e or by selling pledge through an adapter) and pays a fee from the pledge.

## Why RISEx's API blocks the intended design

The plan was to send these permits through RISEx's hosted API like any other order. On testnet the API refused the 388-byte ERC-1271 signature: it accepts 64 or 65 bytes of ECDSA only. That left two variants, both built and run on testnet:

| Variant | Order path | Pre-trade check | Needs from RISE | Lender's risk from one bad order |
| --- | --- | --- | --- | --- |
| Gateway | A gateway contract calls the router on chain | Every order | The order role ([RIP-4](../RIPs/rip-4.md)) | About 5 USDC under the experiment's settings |
| Session key | Borrower's Perps key through the API | None; rules enforced after the trade by a keeper | Nothing | Up to the whole debt |
| **Contract signature** | **Account's own permit through the API** | **Every order** | **[RIP-3](../RIPs/rip-3.md)** | **About 5 USDC** |

The session-key variant is weaker for three reasons we measured on testnet:

- A Perps key can raise leverage to the market maximum (50× on BTC and ETH), and neither the account nor the manager can pin it.
- One crossed trade at the edge of the price band, against another account the borrower owns, can move the whole equity out in one block.
- A revoked key's resting orders stay on the book and can still fill; another key has to cancel them.

RIP-3 would give the gateway's safety with the session key's simplicity: no special role, the hosted API, and the check in every order.

## What ran live on RISE testnet

| Case | Result |
| --- | --- |
| Gateway: builder fee approval, borrower order, reduce-only close | All filled |
| Gateway: liquidation drill | Health line 0.9985 → `startLiquidation` → liquidator close → `liquidate`; account closed, debt repaid in full, lender share price not lower |
| Session key: trading, a breach flagged and cleared, two liquidations | All through the API |
| Contract signature through the API | Refused: `signature must be 64 (compact) or 65 (r+s+v) bytes, got 388` |
