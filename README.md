# RISE Improvement Proposals

By [@degenRobot](https://x.com/degenRobot) · [mattsmart.xyz](https://mattsmart.xyz)

Two draft proposals for [RISEx](https://docs.risechain.com/docs/risex), the perps exchange on RISE, written in the [EIP-1](https://eips.ethereum.org/EIPS/eip-1) format, with worked examples of what each one makes possible.

Protocols such as under-collateralised credit accounts, a synthetic perps book and order hooks are being built as experiments on RISE testnet today. Each is blocked by one of two things. The hosted API will not relay an order signed by a smart contract, and there is no public way for a contract to get the order role.

## Proposals

| RIP | Title | Changes | Status |
| --- | --- | --- | --- |
| [3](RIPs/rip-3.md) | Contract signatures on the hosted API | Off-chain API only; the router already decodes ERC-1271 permits | Draft |
| [4](RIPs/rip-4.md) | Whitelisting contracts for the order role | A governance process for AccessManager role 14; no code change | Draft |

RISE already publishes [RIP-1: Modular Sub-accounts](https://docs.risechain.com/docs/risex/rips/rip-1) and [RIP-2: Permissionless Portfolio Margin](https://docs.risechain.com/docs/risex/rips/rip-2), so these drafts take the next free numbers. RISE assigns the final ones.

RIP-3 lets any contract account set its own rules for which orders it signs, with no special role. RIP-4 is for the smaller set of designs that must place an order and change their own state in the same transaction. [the-two-asks.pdf](RIPs/the-two-asks.pdf) puts both on one page.

## What RISE gets

The proposals ask RISE for an API change and a grant process. This is what comes back.

- **Accounts that cannot trade today.** Of 2,715 recently active RISEx accounts we sampled, none was a contract. Multisig treasuries, passkey wallets and lending protocols have no path through the API until RIP-3.
- **Order flow from products RISE does not have to build.** The synthetic book rests a post-only order at the RISEx mid and sends its closes and liquidations to RISEx's book. A margin product closes its positions there. All of it arrives as ordinary orders under a builder code.
- **Leverage and collateral risk that stays outside RISEx's risk engine.** On a fork, traders ran at 94× inside the synthetic book while RISEx margined the book's one account at 4×. A 3% gap bankrupted every trader and cost the book's pool 8%; the account's equity was still 17 times RISEx's maintenance margin. In a second fork run, a portfolio-margin account was liquidated by its own keeper in one transaction while RISEx's liquidator still counted it healthy. RISEx's margin and liquidation code runs unchanged in both, as the backstop.

Two limits. Trades matched inside the synthetic book never reach RISEx, so the venue gets net flow, not gross. And risk moved to a third party's pool is still risk: the security sections of both RIPs say what RISE should ask of anyone it lets in.

## Examples

| Example | Needs | What it shows | Status |
| --- | --- | --- | --- |
| [Synthetic book](examples/synthetic-book.md) ([PDF](examples/synthetic-book.pdf)) | RIP-4 | A Papertrade-style perps book where traders match each other at the RISEx mid and the rest rests on RISEx. LPs hold no directional exposure, and leverage above RISEx's own sits in the book's pool | Live on testnet |
| [Hooks](examples/hooks.md) | RIP-4 (RIP-3 for pre-trade only) | Pluggable checks before and after every order: risk caps, daily loss limits, delegated trading | Live on testnet |
| [Portfolio margin liquidation](examples/portfolio-margin.md) | RIP-4 | The atomic close, withdraw and repay that RISE's RIP-2 describes, with RISEx's own margin check and liquidator unchanged | Mainnet fork |
| [Credit accounts](examples/credit-accounts.md) | RIP-3 (or RIP-4 today) | Lending to perps traders, where an order that would break the loan is an invalid signature | Live on testnet (gateway variant) |
| [Smart wallets and more](examples/smart-wallets-and-more.md) | RIP-3 | Passkey wallets (RISE Wallet, Porto, Coinbase Smart Wallet), Safe, agent wallets, permissionless stop-losses and TWAPs | Proposed uses |

[contract-accounts.pdf](examples/contract-accounts.pdf) covers credit accounts, portfolio margin liquidation, hooks and smart wallets in one document.

The examples are experiments on RISE testnet, built under the working name Dojima. None is a live product. The pages quote short excerpts from the testnet contracts; the full reference code is not in this repository yet.

## Open questions for RISE

1. Does the API already have, or plan, a contract-signature path? If so, RIP-3 becomes a spec for it.
2. What `MAX_1271_GAS` and `MAX_SIGNATURE_BYTES` would RISE accept?
3. Does the current mainnet code still trade for `_msgSender()` in `PerpsManager.placeOrder`? RIP-4's reading of the role's reach rests on the February 2026 source.
4. Would RISE consider a narrower role scoped to `PerpsManager.placeOrder` and `cancelOrder`, separate from router access?
5. Is there a venue-side limit a contract account can set and a session key cannot lift, such as a leverage pin? That would reduce how much RIP-3 needs to carry.
6. Where should RIPs be discussed: a forum, a GitHub repository, or the docs site?

## Articles by the author

Three articles by [@degenRobot](https://x.com/degenRobot) on why RISE builds the chain and the exchange together, and why composability with the order book matters:

- [Putting DeFi on steroids & the death of tardfi](https://x.com/degenRobot/status/1993652483152068697) (26 November 2025): fast execution, native order books and an invisible wallet built on Porto, with passkeys and scoped session keys.
- [Unleash the Money Legos](https://x.com/degenRobot/status/1995836883721748807) (2 December 2025): DeFi Summer as an experiment in composability, and order books as the next native lego.
- [Why would RISE build both the chain and the exchange?](https://x.com/degenRobot/status/2011455021616083304) (14 January 2026): vertical integration, and why synchronous shared state between the order book and the rest of DeFi is the architecture.

These RIPs ask for the two sockets a money lego needs. Other accounts must be able to sign for themselves (RIP-3), and other contracts must be able to trade in the same transaction (RIP-4).

## Contributing

Open an issue or a pull request. New proposals start from [TEMPLATE.md](TEMPLATE.md). To rebuild the PDFs, run `scripts/build-pdfs.sh` (needs Google Chrome or Brave).

## Licence

Text released under [CC0 1.0](LICENSE).
