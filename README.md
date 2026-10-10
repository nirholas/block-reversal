# BlockReversal

<!-- three.ws:badges -->
[![GitHub stars](https://img.shields.io/github/stars/nirholas/block-reversal?style=flat&logo=github)](https://github.com/nirholas/block-reversal/stargazers) [![License](https://img.shields.io/github/license/nirholas/block-reversal?style=flat)](https://github.com/nirholas/block-reversal/blob/HEAD/LICENSE) [![Last commit](https://img.shields.io/github/last-commit/nirholas/block-reversal?style=flat)](https://github.com/nirholas/block-reversal/commits) [![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen?style=flat)](https://github.com/nirholas/block-reversal/pulls) [![AI agent friendly](https://img.shields.io/badge/AI%20agents-AGENTS.md%20%2B%20llms.txt-6d5dfc?style=flat)](https://github.com/nirholas/block-reversal/blob/HEAD/AGENTS.md)
<!-- /three.ws:badges -->


**Charges the swap that unwinds a block's own price move, which is the only leg of a sandwich that can be identified without knowing who anybody is.**

A production Uniswap v4 hook. It prices every swap by overriding the pool's LP fee, so the value it captures is paid to in-range liquidity and never to the hook. No owner, no pause switch, no upgrade path.

- **Site:** https://block-reversal.pages.dev
- **Catalogue:** https://hookforge.pages.dev
- **Contract:** [`src/hooks/BlockReversalHook.sol`](src/hooks/BlockReversalHook.sol)
- **Licence:** Apache-2.0

## How it works

Anti-sandwich designs almost all try to identify the attacker: track an address, require a bond, tax a trader who reverses direction. Every one of them is defeated by a second EOA, which costs a bot nothing. Identity is the wrong thing to look at, because a sandwich is not a property of who is trading.

It is a property of the price path. A sandwich has a shape: within one block, the price moves away from where the block opened and then comes back. The profitable leg is always the one that comes back, because that is where the position is closed.

This hook never asks who is trading. It records where the price stood when the block opened, watches how far it has travelled since, and prices any swap that moves it back toward the opening more expensively the more of that move it is unwinding. The victim is not charged: their swap is the one that moves the price away.

Nor is the attacker's opening leg. Only the close pays, which is the leg that has something to pay with. The same charge lands on an honest trader who happens to trade against the block's direction, and that is not a flaw to apologise for.

Such a trader is buying at a price that an earlier trade in the same block improved for them, at the expense of the liquidity providers who supplied it. Returning part of that improvement to those providers is the correct answer whether the trader meant to sandwich anybody or not. The fee is an LP fee, so that is exactly where it goes.

Nothing here needs an oracle, an auction, a keeper, a bond, a private mempool, or a way to tell one address from another. It reads the pool's own tick against where the block opened, and that is all.

## Prior art

Sandwich-resistant AMM designs reorder or batch within a block. Encrypted mempools (Shutter, SUAVE) hide the order. Auction-based capture (am-AMM, MEV-Share, Diamond) sells or reclaims the backrun. Volatility-indexed dynamic fees raise the fee for everybody when the pool is moving. Pricing an individual swap by how much of the current block's own price move it is unwinding, so the closing leg pays and the victim does not, with no identity and no auction, is the contribution here.

## Where it does not help

An honest trader who trades against the block's direction pays the surcharge too. That is deliberate and it is the real cost: the mechanism cannot distinguish a sandwich close from an ordinary trade in the same direction, because at the level it observes them they are the same event. It also does nothing about a sandwich split across two blocks, which is a different and much riskier attack for the attacker to run. And a pool with a large `thresholdTicks` is protected only against sandwiches big enough to cross it, while a small one charges ordinary two-way flow more often; that trade is the pool's to make.

## Using it

Uniswap v4 removed `hookData` from `initialize`, so per-pool parameters arrive out of band. Fix them for a pool key whose pool does not exist yet, then initialize. Nobody can change them afterwards, including you.

```solidity
hook.configure(
    key,
    BlockReversalHook.Config({
        baseFee: /* uint24 */ 0,
        maxSurcharge: /* uint24 */ 0,
        thresholdTicks: /* int24 */ 0,
        halfPointTicks: /* int24 */ 0
    })
);

poolManager.initialize(key, startingSqrtPriceX96);
```

The pool's `fee` field must be `LPFeeLibrary.DYNAMIC_FEE_FLAG`. The hook rejects a pool initialized without it.

### Parameters

| Parameter | Type | Units |
| --- | --- | --- |
| `baseFee` | `uint24` | hundredths of a bip (`3000` = 0.30%) |
| `maxSurcharge` | `uint24` | hundredths of a bip (`3000` = 0.30%) |
| `thresholdTicks` | `int24` | ticks |
| `halfPointTicks` | `int24` | ticks |

## What it reverts with

| Error | Meaning |
| --- | --- |
| `FeeTooLarge()` | A surcharge cannot push the total past the protocol's own ceiling on an LP fee. |
| `InvalidThreshold()` | A threshold or half point of zero would make the surcharge fire on any move at all. |
| `NotDynamicFee()` | The hook was attempted to be initialized with a non-dynamic fee. |
| `PoolAlreadyInitialized()` | The pool already exists, so its configuration is final. |
| `PoolNotConfigured()` | The pool was initialized without a configuration for this hook. |
| `SafeCastOverflowedIntToUint(int256)` | An int value doesn't fit in a uint of `bits` size. |
| `SafeCastOverflowedUintDowncast(uint8,uint256)` | Value doesn't fit in a uint of `bits` size. |

## The callbacks it claims

Uniswap v4 reads a hook's permissions from the low fourteen bits of its own address, which is why deploying one means mining a CREATE2 salt. This hook claims 2 of the fourteen:

- `afterInitialize`
- `beforeSwap`

Mask: `0x1080`, so every deployment of this hook has an address ending in those bits.

## It says what it is, on-chain

Every hook in this family implements `IHookMetadata`: four view functions that let an indexer, a wallet, a router or an agent identify a hook from its address alone, with no registry in the loop.

```bash
cast call $HOOK "hookName()(string)"    # BlockReversal
cast call $HOOK "hookVersion()(string)" # 1.0.0
cast call $HOOK "specURI()(string)"     # the machine-readable manifest
cast call $HOOK "hookTags()(string[])"  # mev, anti-sandwich, dynamic-fee, oracle-free, no-admin
```

The manifest this repository ships as [`hook.json`](hook.json) is what `specURI()` points at.

## Build and test

```bash
git clone --recurse-submodules https://github.com/nirholas/block-reversal
cd block-reversal
forge build
forge test
```

Foundry 1.7 or newer, Solidity 0.8.26, EVM version `cancun` (Uniswap v4 requires transient storage).

## Deploy

```bash
# Dry run: mines the salt and prints the address without sending anything.
forge script script/Deploy.s.sol --rpc-url $RPC_URL

# For real.
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify
```

Needs `PRIVATE_KEY` in the environment and a funded deployer on the target chain. See [`docs/deploying.md`](docs/deploying.md).

## Status

**Unaudited.** Built to an audited shape, on OpenZeppelin's audited hook bases, and tested against a real `PoolManager`. No third party has reviewed it. Read "where it does not help" above before putting money behind it.

Not affiliated with Uniswap Labs.

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=nirholas/block-reversal&type=Date)](https://www.star-history.com/#nirholas/block-reversal&Date)

<!-- three.ws:growth -->
## Support the project

If block-reversal saves you time, **[star it on GitHub](https://github.com/nirholas/block-reversal)**. Stars are how other developers and AI agents find the repositories worth trusting, and they cost you one click.

Know someone who would use it? [Post on X](https://twitter.com/intent/tweet?text=block-reversal%3A%20Charges%20the%20swap%20that%20unwinds%20a%20block's%20own%20price%20move%2C%20which%20is%20the%20only%20leg%20of%20a%20sandwich%20that&url=https%3A%2F%2Fgithub.com%2Fnirholas%2Fblock-reversal) · [Share on Bluesky](https://bsky.app/intent/compose?text=block-reversal%3A%20Charges%20the%20swap%20that%20unwinds%20a%20block's%20own%20price%20move%2C%20which%20is%20the%20only%20leg%20of%20a%20sandwich%20that%20https%3A%2F%2Fgithub.com%2Fnirholas%2Fblock-reversal) · [Share on LinkedIn](https://www.linkedin.com/sharing/share-offsite/?url=https%3A%2F%2Fgithub.com%2Fnirholas%2Fblock-reversal) · [Submit to Hacker News](https://news.ycombinator.com/submitlink?u=https%3A%2F%2Fgithub.com%2Fnirholas%2Fblock-reversal&t=block-reversal%3A%20Charges%20the%20swap%20that%20unwinds%20a%20block's%20own%20price%20move%2C%20which%20is%20the%20only%20leg%20of%20a%20sandwich%20that) · [Share on Reddit](https://www.reddit.com/submit?url=https%3A%2F%2Fgithub.com%2Fnirholas%2Fblock-reversal&title=block-reversal%3A%20Charges%20the%20swap%20that%20unwinds%20a%20block's%20own%20price%20move%2C%20which%20is%20the%20only%20leg%20of%20a%20sandwich%20that)

## Built for AI agents too

Coding agents and LLM tooling can read this repo directly: [AGENTS.md](./AGENTS.md), [llms.txt](./llms.txt), [llms-full.txt](./llms-full.txt). Point an agent at `https://github.com/nirholas/block-reversal` and it has the context it needs.

## More from the same author

- [All repositories by nirholas](https://github.com/nirholas/nirholas#readme): the full catalog, grouped by topic
- [three.ws](https://three.ws): the platform for 3D AI agents with Solana wallets, a skill marketplace and x402 payments
- Questions or ideas: [open an issue](https://github.com/nirholas/block-reversal/issues) or [start a discussion](https://github.com/nirholas/block-reversal/discussions)

## Contributors

[![Contributors](https://contrib.rocks/image?repo=nirholas/block-reversal)](https://github.com/nirholas/block-reversal/graphs/contributors)

<!-- /three.ws:growth -->
