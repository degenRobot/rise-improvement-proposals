# Examples

Experiments on RISE testnet, and the uses we expect once the proposals land. None is a live product. Each page says which RIP it needs.

| Example | Needs | Status |
| --- | --- | --- |
| [Synthetic book](synthetic-book.md) ([PDF](synthetic-book.pdf)) | [RIP-4](../RIPs/rip-4.md) | Live on testnet |
| [Hooks](hooks.md) | [RIP-4](../RIPs/rip-4.md); [RIP-3](../RIPs/rip-3.md) for the pre-trade half | Live on testnet |
| [Portfolio margin liquidation](portfolio-margin.md) | [RIP-4](../RIPs/rip-4.md) | Run on a mainnet fork |
| [Credit accounts](credit-accounts.md) | [RIP-3](../RIPs/rip-3.md), or [RIP-4](../RIPs/rip-4.md) for the gateway variant | Gateway variant live on testnet |
| [Smart wallets and more](smart-wallets-and-more.md) | [RIP-3](../RIPs/rip-3.md) | Proposed uses |

[contract-accounts.pdf](contract-accounts.pdf) collects credit accounts, portfolio margin liquidation, hooks and smart wallets in one document.

Figures marked "live" were measured on RISE testnet (chain 11155931) between 13 and 14 November 2026. Figures marked "fork" come from local forks of RISE testnet or mainnet running RISEx's deployed contracts, where the fork grants the order role by writing AccessManager storage. The 100× book run and the portfolio-margin run are from 17 November 2026; their test contracts are not published.
