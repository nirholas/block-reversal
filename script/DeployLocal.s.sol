// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {HookMiner} from "@uniswap/v4-periphery/test/shared/HookMiner.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {DemoToken} from "src/demo/DemoToken.sol";
import {DemoRouter} from "src/demo/DemoRouter.sol";
import {BlockReversalHook} from "src/hooks/BlockReversalHook.sol";

/**
 * @title DeployLocal
 * @notice Brings the whole demo up on a local chain: a PoolManager, two faucet tokens, a router a browser can drive,
 * this hook, a configured pool and enough liquidity to trade it.
 *
 * @dev A hook nobody can click is a blog post. This is what makes the site's "Try it" section work without anybody
 * spending anything on a public network:
 *
 *   anvil &
 *   forge script script/DeployLocal.s.sol --rpc-url http://127.0.0.1:8545 --broadcast \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
 *
 * The last line is the JSON the site's web/src/deployments.json wants. Anvil's first account is pre-funded and its
 * key is public by design; never use it anywhere real.
 */
contract DeployLocal is Script {
    uint160 internal constant FLAGS = uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG);
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;
    uint256 internal constant Q96 = 1 << 96;

    PoolManager internal manager;
    DemoToken internal weth;
    DemoToken internal dai;
    DemoRouter internal router;
    BlockReversalHook internal hook;
    PoolKey internal key;

    function run() external {
        vm.startBroadcast();

        manager = new PoolManager(msg.sender);
        weth = new DemoToken("Hook Demo Ether", "hETH");
        dai = new DemoToken("Hook Demo Dollar", "hUSD");
        router = new DemoRouter(IPoolManager(address(manager)));

        (address predicted, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER, FLAGS, type(BlockReversalHook).creationCode, abi.encode(IPoolManager(address(manager)))
        );
        hook = new BlockReversalHook{salt: salt}(IPoolManager(address(manager)));
        require(address(hook) == predicted, "hook landed at an unexpected address");

        _openPool();
        vm.stopBroadcast();

        string memory config = string.concat(
                '{"chains":{"31337":{"rpcUrl":"http://127.0.0.1:8545","poolManager":"', vm.toString(address(manager)),
                '","router":"', vm.toString(address(router)),
                '","hook":"', vm.toString(address(hook)),
                '","currency0":"', vm.toString(Currency.unwrap(key.currency0)),
                '","currency1":"', vm.toString(Currency.unwrap(key.currency1)),
                '","poolId":"', vm.toString(PoolId.unwrap(key.toId())),
                '","fee":', vm.toString(uint256(key.fee)),
                ',"tickSpacing":', vm.toString(uint256(uint24(key.tickSpacing))),
                ',"zeroForOne":true,"faucet":true,"demoSwapAmount":"10000000000000000"}}}'
        );

        // Written rather than printed, so bringing the demo up is one command and not a copy-paste. The site's
        // build merges this over whatever is baked in, and .gitignore keeps it out of the repository: it names
        // addresses that exist only on the machine that ran this.
        vm.writeFile("web/local.json", config);

        console2.log("Wrote web/local.json. Now: node web/build.mjs && npx serve web/dist");
        console2.log(config);
    }

    function _openPool() private {
        (Currency currency0, Currency currency1) = address(weth) < address(dai)
            ? (Currency.wrap(address(weth)), Currency.wrap(address(dai)))
            : (Currency.wrap(address(dai)), Currency.wrap(address(weth)));

        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        hook.configure(key, BlockReversalHook.Config({baseFee: 500, maxSurcharge: 9_500, thresholdTicks: 20, halfPointTicks: 60}));
        router.initialize(key, SQRT_PRICE_1_1);

        weth.claim();
        dai.claim();
        IERC20(Currency.unwrap(currency0)).approve(address(router), type(uint256).max);
        IERC20(Currency.unwrap(currency1)).approve(address(router), type(uint256).max);
        router.modifyLiquidity(
            key,
            ModifyLiquidityParams({tickLower: -60000, tickUpper: 60000, liquidityDelta: 5e18, salt: bytes32(0)}),
            ""
        );
    }
}
