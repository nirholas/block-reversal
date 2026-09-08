# Integrating BlockReversal

## From Solidity

```solidity
import {BlockReversalHook} from "block-reversal/src/hooks/BlockReversalHook.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";

PoolKey memory key = PoolKey({
    currency0: currencyA,          // must sort below currency1
    currency1: currencyB,
    fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
    tickSpacing: 60,
    hooks: IHooks(address(hook))
});

hook.configure(key, BlockReversalHook.Config({ /* see the README */ }));
poolManager.initialize(key, startingSqrtPriceX96);
```

## From TypeScript

```ts
import {getHook, hookAddress, poolKeyFor, poolId} from "@hookforge/sdk";

const hook = getHook("block-reversal");
const address = hookAddress("block-reversal", 8453);              // Base
const key = poolKeyFor({
  hook: address,
  currencyA: USDC,
  currencyB: WETH,
  tickSpacing: 60,
  dynamicFee: true,
});
console.log(poolId(key));
```

## Identifying the hook from an address

Any caller holding only a hook address can find out what it is, without a registry:

```solidity
IHookMetadata(hookAddress).hookName();   // "BlockReversal"
IHookMetadata(hookAddress).specURI();    // points at hook.json
```

The permission bits are in the address itself, so a caller can also decode what the hook participates in with no call at all:

```ts
import {permissionsOf} from "@hookforge/sdk";
permissionsOf(address);
```

## Things that will bite you

- **The pool must be initialized with the dynamic-fee flag.** The hook reverts at `afterInitialize` otherwise. This is the single most common integration failure.
- **Configure before you initialize.** The parameters are fixed for the pool's lifetime, and a pool the hook was never configured for cannot be created at all.
- **Anyone can configure a key that has no pool yet.** If someone front-runs your configuration with terms you did not want, pick a different `tickSpacing` and configure that instead. It is a different pool id and it costs them their gas.
- **Deterministic addresses are not deployments.** An address published before a deploy is where the hook *will* be. There is no code at it until the deploy runs.

More at https://block-reversal.pages.dev.
